import Foundation
import Combine

@MainActor
final class RSSStore: ObservableObject {
    static let shared = RSSStore()
    static let cloudKey = "rss.state.v1"
    static let localKey = "rss.localState.v1"
    @Published private(set) var state: RSSSyncState
    @Published private(set) var articles: [RSSArticle] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var syncMessage = "フィード一覧と最近1,000件の既読・未読の変更をiCloudで同期します。"
    private let defaults: UserDefaults
    private let cloud: SettingsCloudStore
    private let cacheURL: URL?
    private var observer: NSObjectProtocol?
    private var accountGeneration = UUID()
    private var refreshRequested = false

    var feeds: [RSSFeed] {
        state.feeds.values.compactMap(\.value).sorted {
            $0.title == $1.title ? $0.url < $1.url : $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    init(defaults: UserDefaults = .standard, cloud: SettingsCloudStore = NSUbiquitousKeyValueStore.default,
         cacheURL: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("rss-articles.json")) {
        self.defaults = defaults
        self.cloud = cloud
        self.cacheURL = cacheURL
        state = Self.decode(defaults.data(forKey: Self.localKey)) ?? RSSSyncState()
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode([RSSArticle].self, from: data) {
            articles = cached.filter { state.feeds[$0.feedURL]?.value != nil }
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
        articles.removeAll { $0.feedURL == feed.url }
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
        let generation = accountGeneration
        errors = [:]
        // Sequential requests avoid overwhelming sites and keep cancellation straightforward.
        for feed in feeds {
            guard !Task.isCancelled, generation == accountGeneration else { return }
            do {
                let url = try RSSURLs.validated(feed.url)
                let parsed = try await (feed.isWebsite ? WebsiteArticleClient.fetch(url, selector: feed.linkSelector) : RSSClient.fetch(url))
                guard !Task.isCancelled, generation == accountGeneration else { return }
                guard state.feeds[feed.url]?.value == feed else { continue }
                replaceArticles(parsed.articles, for: feed.url)
            } catch {
                guard !Task.isCancelled, generation == accountGeneration else { return }
                if state.feeds[feed.url]?.value != nil { errors[feed.url] = error.localizedDescription }
            }
        }
        cache()
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
