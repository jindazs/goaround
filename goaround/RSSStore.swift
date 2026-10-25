import Foundation
import Combine

@MainActor
final class RSSStore: ObservableObject {
    static let shared: RSSStore = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reader-ui-fixture") { return readerFixture() }
        #endif
        return RSSStore()
    }()
    static let cloudKey = "rss.state.v1"
    static let localKey = "rss.localState.v1"
    @Published private(set) var state: RSSSyncState
    @Published private(set) var articles: [RSSArticle] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var articleContents: [String: ArticleContent] = [:]
    @Published private(set) var contentErrors: [String: String] = [:]
    @Published private(set) var contentPendingCount = 0
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var syncMessage = "フィード一覧と最近1,000件の既読・未読の変更をiCloudで同期します。"
    private let defaults: UserDefaults
    private let cloud: SettingsCloudStore
    private let cacheURL: URL?
    private var observer: NSObjectProtocol?
    private var accountGeneration = UUID()
    private var refreshRequested = false
    private let contentCache: ArticleContentCache
    private let fetchFeed: @Sendable (RSSFeed) async throws -> RSSParsedFeed
    private let fetchContent: @Sendable (RSSArticle) async throws -> ArticleContent
    private var contentTask: Task<Void, Never>?
    private var contentTaskID = UUID()
    private var contentRequested = false
    private var contentAttempts = Set<String>()

    var feeds: [RSSFeed] {
        state.feeds.values.compactMap(\.value).sorted {
            $0.title == $1.title ? $0.url < $1.url : $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    init(defaults: UserDefaults = .standard, cloud: SettingsCloudStore = NSUbiquitousKeyValueStore.default,
         cacheURL: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("rss-articles.json"),
         contentCache: ArticleContentCache = .standard,
         fetchContent: @escaping @Sendable (RSSArticle) async throws -> ArticleContent = { try await ArticleContentClient.fetch($0) },
         fetchFeed: @escaping @Sendable (RSSFeed) async throws -> RSSParsedFeed = { feed in
             let url = try RSSURLs.validated(feed.url)
             return try await (feed.isWebsite ? WebsiteArticleClient.fetch(url, selector: feed.linkSelector) : RSSClient.fetch(url))
         }) {
        self.defaults = defaults
        self.cloud = cloud
        self.cacheURL = cacheURL
        self.contentCache = contentCache
        self.fetchContent = fetchContent
        self.fetchFeed = fetchFeed
        state = Self.decode(defaults.data(forKey: Self.localKey)) ?? RSSSyncState()
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode([RSSArticle].self, from: data) {
            articles = cached.filter { state.feeds[$0.feedURL]?.value != nil }
        }
        for article in articles.prefix(300) {
            if let content = contentCache.load(article) { articleContents[article.id] = content }
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            Task { @MainActor [weak self] in self?.cloudChanged(reason: reason) }
        }
        synchronize()
    }

    func cloudChanged(reason: Int?) {
        if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
            syncMessage = "iCloudの同期容量を超えました。変更はこの端末に保存されています。"
        } else if reason == NSUbiquitousKeyValueStoreAccountChange {
            // Keep a local backup, but never merge the previous account into the new account.
            defaults.set(defaults.data(forKey: Self.localKey), forKey: "rss.previousAccountBackup")
            accountGeneration = UUID()
            contentTask?.cancel()
            contentTask = nil
            contentTaskID = UUID()
            contentAttempts = []
            contentRequested = false
            contentErrors = [:]
            articleContents = [:]
            contentPendingCount = 0
            contentCache.removeAll()
            state = Self.decode(cloud.data(forKey: Self.cloudKey)) ?? RSSSyncState()
            articles = []
            errors = [:]
            persist()
            cache()
        } else {
            reconcile()
        }
    }

    func synchronize() {
        let available = cloud.synchronize()
        syncMessage = available
            ? "フィード一覧と最近1,000件の既読・未読の変更をiCloudで同期します。"
            : "iCloudを利用できません。変更はこの端末に保存されています。"
        reconcile()
    }

    func reconcile() {
        if let data = cloud.data(forKey: Self.cloudKey) {
            guard let remote = Self.decode(data) else {
                syncMessage = "iCloudのRSSデータを読み取れません。この端末のデータは保持しています。"
                return
            }
            var merged = state
            merged.merge(remote)
            if merged != state { state = merged }
        }
        articles.removeAll { state.feeds[$0.feedURL]?.value == nil }
        let retained = Set(articles.map(\.id))
        articleContents = articleContents.filter { retained.contains($0.key) }
        persist()
        publish()
    }

    func addFeed(_ text: String, website: Bool = false, selector: String? = nil) async throws {
        let url = try RSSURLs.validated(text, removeFragment: true)
        guard state.feeds[url.absoluteString]?.value != nil || feeds.count < 100 else { throw RSSFailure.limit }
        let generation = accountGeneration
        let parsed = try await (website ? WebsiteArticleClient.fetch(url, selector: selector) : RSSClient.fetch(url))
        try Task.checkCancellation()
        guard generation == accountGeneration else { throw CancellationError() }
        // Recheck after the network suspension, since another device may have added feeds.
        guard state.feeds[url.absoluteString]?.value != nil || feeds.count < 100 else { throw RSSFailure.limit }
        state.feeds[url.absoluteString] = RSSChange(value: RSSFeed(url: url.absoluteString, title: parsed.title, sourceKind: website ? "website" : nil,
                                                                  linkSelector: website ? selector : nil), date: nextDate())
        replaceArticles(parsed.articles, for: url.absoluteString)
        persist()
        publish()
        cache()
        scheduleContentPrefetch()
    }

    /// Import subscriptions offline in one batch; article fetching is a separate operation.
    func importOPML(_ data: Data) throws -> OPMLImportResult {
        var result = try OPMLParser.parse(data)
        reconcile()
        var count = feeds.count
        for feed in result.feeds {
            if state.feeds[feed.url]?.value != nil {
                result.duplicates += 1
            } else if count >= 100 {
                result.overLimit += 1
            } else {
                state.feeds[feed.url] = RSSChange(value: feed, date: nextDate())
                count += 1
                result.added += 1
            }
        }
        if result.added > 0 {
            persist()
            publish()
        }
        return result
    }

    func removeFeed(_ feed: RSSFeed) {
        state.feeds[feed.url] = RSSChange(value: nil, date: nextDate())
        let removed = Set(articles.filter { $0.feedURL == feed.url }.map(\.id))
        articles.removeAll { $0.feedURL == feed.url }
        articleContents = articleContents.filter { !removed.contains($0.key) }
        errors.removeValue(forKey: feed.url)
        persist()
        publish()
        cache()
    }

    func isRead(_ article: RSSArticle) -> Bool { state.reads[article.id]?.value == true }

    func setRead(_ read: Bool, articles: [RSSArticle]) {
        for article in articles {
            state.reads[article.id] = RSSChange(value: read, date: nextDate())
        }
        state.compact()
        persist()
        publish()
    }

    func refresh() async {
        guard !isRefreshing else { refreshRequested = true; return }
        isRefreshing = true
        defer {
            isRefreshing = false
            if refreshRequested {
                refreshRequested = false
                Task { await self.refresh() }
            }
        }
        synchronize()
        contentAttempts = []
        contentErrors = [:]
        scheduleContentPrefetch()
        let generation = accountGeneration
        errors = [:]
        // Sequential requests avoid overwhelming sites and keep cancellation straightforward.
        for feed in feeds {
            guard !Task.isCancelled, generation == accountGeneration else { return }
            do {
                let parsed = try await fetchFeed(feed)
                guard !Task.isCancelled, generation == accountGeneration else { return }
                guard state.feeds[feed.url]?.value == feed else { continue }
                replaceArticles(parsed.articles, for: feed.url)
                scheduleContentPrefetch()
            } catch {
                guard !Task.isCancelled, generation == accountGeneration else { return }
                if state.feeds[feed.url]?.value != nil { errors[feed.url] = error.localizedDescription }
            }
        }
        cache()
    }

    /// Opening the reader only reads local storage. It never requests the original URL.
    func prepareToRead(_ article: RSSArticle) {
        if articleContents[article.id] == nil, let content = contentCache.load(article) {
            articleContents[article.id] = content
        }
    }

    func scheduleContentPrefetch() {
        guard contentTask == nil else { contentRequested = true; return }
        let candidates = articles.prefix(100).filter {
            $0.url != nil && !contentAttempts.contains($0.id) &&
            (articleContents[$0.id].map { Date().timeIntervalSince($0.fetchedAt) > 86_400 } ?? true)
        }
        guard !candidates.isEmpty else { return }
        let generation = accountGeneration
        let taskID = UUID()
        contentTaskID = taskID
        contentPendingCount = candidates.count
        contentAttempts.formUnion(candidates.map(\.id))
        let fetcher = fetchContent
        contentTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.contentTaskID == taskID {
                    self.contentTask = nil
                    self.contentPendingCount = 0
                    self.contentCache.trim()
                    if self.contentRequested {
                        self.contentRequested = false
                        self.scheduleContentPrefetch()
                    }
                }
            }
            await withTaskGroup(of: (String, ArticleContent?, String?).self) { group in
                var iterator = candidates.makeIterator()
                func enqueue(_ article: RSSArticle) {
                    group.addTask {
                        do { return (article.id, try await fetcher(article), nil) }
                        catch { return (article.id, nil, error.localizedDescription) }
                    }
                }
                for _ in 0..<3 { if let article = iterator.next() { enqueue(article) } }
                while let (id, content, error) = await group.next() {
                    guard !Task.isCancelled, generation == self.accountGeneration else { group.cancelAll(); return }
                    if self.articles.contains(where: { $0.id == id }) {
                        if let content {
                            self.articleContents[id] = content
                            self.contentCache.save(content)
                            self.contentErrors.removeValue(forKey: id)
                        } else { self.contentErrors[id] = error }
                    }
                    self.contentPendingCount = max(0, self.contentPendingCount - 1)
                    if let article = iterator.next() { enqueue(article) }
                }
            }
        }
    }

    private func nextDate() -> Date {
        let latest = max(state.feeds.values.map(\.date).max() ?? .distantPast,
                         state.reads.values.map(\.date).max() ?? state.readCutoff)
        return max(Date(), latest.addingTimeInterval(0.001))
    }

    private func replaceArticles(_ incoming: [RSSArticle], for feed: String) {
        articles.removeAll { $0.feedURL == feed }
        articles.append(contentsOf: incoming)
        articles.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.localKey) }
    }

    private func publish() {
        // A cached remote update may arrive before its notification is handled.
        // Merge it immediately before writing so local actions cannot erase it.
        if let data = cloud.data(forKey: Self.cloudKey) {
            guard let remote = Self.decode(data) else {
                syncMessage = "iCloudのRSSデータを読み取れません。この端末のデータは保持しています。"
                return
            }
            var merged = state
            merged.merge(remote)
            if merged != state { state = merged; persist() }
        }
        guard !state.feeds.isEmpty || !state.reads.isEmpty,
              let data = try? JSONEncoder().encode(state) else { return }
        let pagesSize = cloud.data(forKey: WebSiteSettingsSync.cloudKey)?.count ?? 0
        guard data.count + pagesSize < 950_000 else {
            syncMessage = "iCloudの同期容量が不足しています。変更はこの端末に保存されています。"
            return
        }
        // Compare decoded values: JSON dictionary ordering is not stable.
        if Self.decode(cloud.data(forKey: Self.cloudKey)) != state { cloud.set(data, forKey: Self.cloudKey) }
    }

    private func cache() {
        guard let cacheURL, let data = try? JSONEncoder().encode(articles) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static func decode(_ data: Data?) -> RSSSyncState? {
        guard let data, data.count < 1_000_000,
              let state = try? JSONDecoder().decode(RSSSyncState.self, from: data), state.version == 1,
              state.reads.count <= 1000,
              state.feeds.allSatisfy({ key, record in
                  (try? RSSURLs.validated(key)) != nil && (record.value == nil || record.value?.url == key)
              }) else { return nil }
        return state
    }
}

#if DEBUG
private final class ReaderFixtureCloud: SettingsCloudStore {
    private var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ value: Data?, forKey key: String) { values[key] = value }
    func synchronize() -> Bool { true }
}

extension RSSStore {
    private static func readerFixture() -> RSSStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReaderUITest")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "ReaderUITest")!
        defaults.removePersistentDomain(forName: "ReaderUITest")
        let feed = RSSFeed(url: "https://reader-test.invalid/feed", title: "オフラインテスト")
        let article = RSSArticle(id: "reader-fixture", feedURL: feed.url, title: "端末内で読める記事", url: URL(string: "https://reader-test.invalid/article")!, summary: "保存された要約です。", date: Date(timeIntervalSince1970: 1792886400))
        var state = RSSSyncState()
        state.feeds[feed.url] = RSSChange(value: feed, date: Date())
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.localKey)
        let list = root.appendingPathComponent("articles.json")
        try? JSONEncoder().encode([article]).write(to: list, options: .atomic)
        let cache = ArticleContentCache(directory: root.appendingPathComponent("bodies"))
        cache.save(ArticleContent(articleID: article.id, sourceURL: article.url!, title: article.title,
            blocks: [.init(kind: .heading, text: "保存済みの本文"),
                     .init(kind: .paragraph, text: "これは事前に取得して端末に保存した記事本文です。記事をタップしても元サイトへの接続を行わず、アプリ内のレイアウトですぐに表示されます。"),
                     .init(kind: .quote, text: "見出し・段落・引用も端末内で表示します。")]))
        return RSSStore(defaults: defaults, cloud: ReaderFixtureCloud(), cacheURL: list, contentCache: cache,
            fetchContent: { _ in throw ArticleContentError.noBody },
            fetchFeed: { _ in RSSParsedFeed(title: feed.title, articles: [article]) })
    }
}
#endif
