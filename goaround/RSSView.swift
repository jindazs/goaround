import SwiftUI
import SafariServices
import UniformTypeIdentifiers

struct RSSView: View {
    @ObservedObject private var store = RSSStore.shared
    @State private var unreadOnly = false
    @State private var selectedFeed = ""
    @State private var search = ""
    @State private var showFeeds = false
    @State private var showSearch = false
    @State private var selectedArticle: RSSArticle?
    // Keep automatically read rows for this browsing session so List does not collapse above the viewport.
    @State private var scrollReadIDs = Set<String>()
    @State private var scrollTracker = RSSScrollReadTracker()
    @State private var articleFrames: [String: CGRect] = [:]
    @State private var listViewport = CGRect.zero
    @StateObject private var scrollObserver = RSSListScrollObserver()
    @State private var scrollIdleTask: Task<Void, Never>?

    private var visibleArticles: [RSSArticle] {
        store.articles.filter {
            (selectedFeed.isEmpty || $0.feedURL == selectedFeed) &&
            (!unreadOnly || !store.isRead($0) || scrollReadIDs.contains($0.id)) &&
            (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.summary.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !store.errors.isEmpty {
                    Section("取得できなかったフィード") {
                        ForEach(store.errors.keys.sorted(), id: \.self) { url in
                            VStack(alignment: .leading) {
                                Text(store.feeds.first(where: { $0.url == url })?.title ?? url)
                                Text(store.errors[url] ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if store.feeds.isEmpty {
                    ContentUnavailableView {
                        Label("RSSを登録しましょう", systemImage: "dot.radiowaves.left.and.right")
                    } description: {
                        Text("RSS/AtomやWebサイトの記事一覧URLを追加すると、ここで記事を読めます。")
                    } actions: {
                        Button("フィードを追加") { showFeeds = true }
                    }
                } else if visibleArticles.isEmpty, !store.isRefreshing {
                    ContentUnavailableView("記事がありません", systemImage: "tray", description: Text("表示条件を変更するか、下に引いて更新してください。"))
                }
                ForEach(visibleArticles) { article in
                    Button {
                        scrollReadIDs.remove(article.id)
                        selectedArticle = article
                        store.prepareToRead(article)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(store.isRead(article) ? Color.clear : Color.accentColor)
                                .frame(width: 7, height: 7).padding(.top, 7)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(article.title).font(.headline)
                                    .foregroundStyle(store.isRead(article) ? .secondary : .primary)
                                if !article.summary.isEmpty {
                                    Text(article.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                                HStack {
                                    Text(store.feeds.first(where: { $0.url == article.feedURL })?.title ?? "")
                                    Spacer()
                                    if let date = article.date { Text(date, style: .date) }
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(store.isRead(article) ? "未読に戻す" : "既読にする") {
                            scrollReadIDs.remove(article.id)
                            store.setRead(!store.isRead(article), articles: [article])
                        }.tint(.blue)
                    }
                    .accessibilityLabel("\(store.isRead(article) ? "既読" : "未読")、\(article.title)")
                    .background(RSSRowScrollProbe(id: article.id, observer: scrollObserver))
                }
                if !store.articles.isEmpty {
                    Section {
                        Button("全てを既読", systemImage: "checkmark.circle.fill") {
                            scrollReadIDs.removeAll()
                            store.setRead(true, articles: store.articles)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("rssBottomMarkAllRead")
                    }
                }
            }
            .onAppear {
                scrollObserver.onUpdate = { frames, viewport, scrolling in
                    articleFrames = frames
                    listViewport = viewport
                    guard selectedArticle == nil, !showFeeds, !showSearch else { return }
                    scrollTracker.update(frames, viewport: viewport, orderedIDs: visibleArticles.map(\.id), scrolling: scrolling)
                    if scrolling { finishScrollingWhenIdle() }
                }
                scrollObserver.resume()
            }
            .onChange(of: visibleArticles.map(\.id)) { _, _ in resetScrollTracking() }
            .onChange(of: unreadOnly) { _, _ in resetScrollReadSession() }
            .onChange(of: selectedFeed) { _, _ in resetScrollReadSession() }
            .onChange(of: search) { _, _ in resetScrollReadSession() }
            .onChange(of: store.isRefreshing) { _, refreshing in
                if refreshing { resetScrollReadSession() }
            }
            .onDisappear { resetScrollReadSession(); scrollObserver.stop() }
            .navigationTitle("RSS")
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("フィード管理", systemImage: "list.bullet") { showFeeds = true }
                        Button(search.isEmpty ? "記事を検索" : "検索：\(search)", systemImage: "magnifyingglass") { showSearch = true }
                        Picker("フィード", selection: $selectedFeed) {
                            Text("すべてのフィード").tag("")
                            ForEach(store.feeds) { Text($0.title).tag($0.url) }
                        }
                        Toggle("未読のみ", isOn: $unreadOnly)
                        if !search.isEmpty || !selectedFeed.isEmpty || unreadOnly {
                            Button("絞り込みを解除", systemImage: "line.3.horizontal.decrease.circle") {
                                search = ""; selectedFeed = ""; unreadOnly = false
                            }
                        }
                        Divider()
                        if store.contentPendingCount > 0 {
                            Text("本文を先読み中（残り\(store.contentPendingCount)件）")
                        }
                        Button(store.isRefreshing ? "更新中…" : "更新", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                            .disabled(store.isRefreshing)
                        Button("表示中の記事をすべて既読にする", systemImage: "checkmark.circle") {
                            let articles = visibleArticles
                            scrollReadIDs.removeAll()
                            store.setRead(true, articles: articles)
                        }.disabled(visibleArticles.isEmpty)
                        Button("すべての記事を既読にする", systemImage: "checkmark.circle.fill") {
                            scrollReadIDs.removeAll()
                            store.setRead(true, articles: store.articles)
                        }.disabled(store.articles.isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("RSSメニュー")
                    .accessibilityValue("\(store.articles.filter { !store.isRead($0) }.count)件未読")
                }
            }
            .sheet(isPresented: $showFeeds) { RSSFeedsView(store: store) }
            .sheet(isPresented: $showSearch) {
                NavigationStack {
                    Form {
                        TextField("記事を検索", text: $search)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("rssSearchQuery")
                        Text("\(visibleArticles.count)件の記事が一致します")
                        Button("検索をクリア") { search = "" }
                    }
                    .navigationTitle("記事を検索")
                    .toolbar { Button("適用") { showSearch = false } }
                }
            }
            .sheet(item: $selectedArticle) { article in
                ArticleReaderView(article: article, store: store)
            }
            .task(id: store.feeds) { await store.refresh() }
            .onChange(of: store.feeds) { _, feeds in
                if !feeds.contains(where: { $0.url == selectedFeed }) { selectedFeed = "" }
            }
        }
    }

    private func finishScrollingWhenIdle() {
        scrollIdleTask?.cancel()
        scrollIdleTask = Task {
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { return }
            guard !Task.isCancelled else { return }
            if scrollObserver.isInteracting { finishScrollingWhenIdle(); return }
            let ids = scrollTracker.drain()
            let read = store.articles.filter { ids.contains($0.id) && !store.isRead($0) && $0.id != selectedArticle?.id }
            guard !read.isEmpty else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if unreadOnly { scrollReadIDs.formUnion(read.map(\.id)) }
                store.setRead(true, articles: read)
            }
        }
    }

    private func resetScrollReadSession() {
        scrollReadIDs.removeAll()
        resetScrollTracking()
    }

    private func resetScrollTracking() {
        scrollIdleTask?.cancel()
        scrollTracker = RSSScrollReadTracker()
        scrollTracker.update(articleFrames, viewport: listViewport, orderedIDs: visibleArticles.map(\.id), scrolling: false)
    }
}

/// Observe UIKit's actual scroll offset; List recycles cells without updating SwiftUI preferences on every scroll.
@MainActor
private final class RSSListScrollObserver: ObservableObject {
    private final class WeakRow {
        weak var view: UIView?
        init(_ view: UIView) { self.view = view }
    }
    var onUpdate: (([String: CGRect], CGRect, Bool) -> Void)?
    var isInteracting: Bool { scrollView.map { $0.isDragging || $0.isDecelerating } ?? false }
    private var rows: [String: WeakRow] = [:]
    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private var scheduled = false
    private var userMoved = false

    func register(_ id: String, view: UIView) {
        rows[id] = WeakRow(view)
        if scrollView == nil {
            var parent = view.superview
            while let current = parent {
                if let scroll = current as? UIScrollView { scrollView = scroll; break }
                parent = current.superview
            }
        }
        resume()
        scheduleUpdate(scrolling: false)
    }
    func unregister(_ id: String, view: UIView) {
        if rows[id]?.view === view { rows.removeValue(forKey: id) }
    }
    func resume() {
        guard observation == nil, let scrollView else { return }
        observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
            self?.scheduleUpdate(scrolling: scroll.isDragging || scroll.isDecelerating)
        }
        scheduleUpdate(scrolling: false)
    }
    func stop() {
        observation?.invalidate()
        observation = nil
        onUpdate = nil
        userMoved = false
    }
    func scheduleUpdate(scrolling: Bool) {
        userMoved = userMoved || scrolling
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            guard let scroll = self.scrollView, scroll.window != nil else { return }
            let moving = self.userMoved
            self.userMoved = false
            let viewport = scroll.bounds.inset(by: scroll.adjustedContentInset)
            var frames: [String: CGRect] = [:]
            for (id, row) in self.rows {
                if let view = row.view, view.window != nil, view.isDescendant(of: scroll) {
                    frames[id] = view.convert(view.bounds, to: scroll)
                }
            }
            self.onUpdate?(frames, viewport, moving)
        }
    }
}

private struct RSSRowScrollProbe: UIViewRepresentable {
    let id: String
    let observer: RSSListScrollObserver
    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.id = id
        view.observer = observer
        return view
    }
    func updateUIView(_ view: ProbeView, context: Context) {
        view.id = id
        view.observer = observer
        if view.window != nil { observer.register(id, view: view) }
    }
    static func dismantleUIView(_ view: ProbeView, coordinator: ()) { view.observer?.unregister(view.id, view: view) }
    final class ProbeView: UIView {
        var id = ""
        weak var observer: RSSListScrollObserver?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { observer?.register(id, view: self) }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            if window != nil { observer?.register(id, view: self) }
        }
    }
}

private struct RSSFeedsView: View {
    @ObservedObject var store: RSSStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var isAdding = false
    @State private var website = false
    @State private var linkSelector = ""
    @State private var error: String?
    @State private var pendingDeletion: RSSFeed?
    @State private var isImportingOPML = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("フィード・サイトを追加") {
                    Picker("取得方法", selection: $website) {
                        Text("RSS / Atom").tag(false)
                        Text("Webサイト").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .disabled(isAdding)
                    TextField(website ? "記事一覧のURL" : "https://example.com/feed.xml", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("rssFeedURL")
                    if website {
                        Text("RSSがないサイトの記事一覧からタイトルとリンクを取得します。公開日時がない記事はサイト内の掲載順で表示します。")
                            .font(.footnote).foregroundStyle(.secondary)
                        DisclosureGroup("自動抽出で見つからない場合") {
                            TextField("記事リンクのCSSセレクタ（任意）", text: $linkSelector)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityIdentifier("websiteLinkSelector")
                            Text("例：article h2 a。サイトのHTMLに合わせてリンクや記事カードを指定できます。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        isAdding = true
                        error = nil
                        Task {
                            defer { isAdding = false }
                            do { try await store.addFeed(url, website: website, selector: linkSelector); url = ""; linkSelector = "" }
                            catch { self.error = error.localizedDescription }
                        }
                    } label: {
                        HStack { Text("追加"); if isAdding { ProgressView() } }
                    }.disabled(isAdding || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                }
                Section {
                    Button("OPMLをインポート", systemImage: "square.and.arrow.down") {
                        isImportingOPML = true
                    }.disabled(isAdding)
                    Text(".opml / .xmlファイルからフィードを追加します。既存のフィードと既読状態は保持されます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("登録フィード（\(store.feeds.count)）") {
                    ForEach(store.feeds) { feed in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(feed.title, systemImage: feed.isWebsite ? "globe" : "dot.radiowaves.left.and.right")
                            if feed.isWebsite { Text("Webサイトから取得").font(.caption2).foregroundStyle(.secondary) }
                            Text(feed.url).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .swipeActions {
                            Button("削除", role: .destructive) { pendingDeletion = feed }
                        }
                    }
                }
                Section("iCloud同期") {
                    Text(store.syncMessage).font(.footnote)
                    Text("同じApple Accountの端末で共有されます。反映には時間がかかる場合があります。記事の取得内容は端末内に保存します。古い既読履歴は未読に戻る場合があります。登録できるフィードは100件までです。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("フィード管理")
            .toolbar { Button("完了") { dismiss() }.disabled(isAdding) }
            .interactiveDismissDisabled(isAdding)
            .fileImporter(isPresented: $isImportingOPML, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                do {
                    guard let fileURL = try result.get().first else { return }
                    let accessed = fileURL.startAccessingSecurityScopedResource()
                    defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
                    let file = try FileHandle(forReadingFrom: fileURL)
                    defer { try? file.close() }
                    let data = try file.read(upToCount: OPMLParser.maxBytes + 1) ?? Data()
                    importMessage = try store.importOPML(data).message
                } catch {
                    importMessage = error.localizedDescription
                }
            }
            .alert("OPMLインポート", isPresented: Binding(
                get: { importMessage != nil }, set: { if !$0 { importMessage = nil } }
            )) {
                Button("OK") { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
            .confirmationDialog("このフィードをすべての端末から削除しますか？", isPresented: Binding(
                get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
            ), titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    if let feed = pendingDeletion { store.removeFeed(feed) }
                    pendingDeletion = nil
                }
            }
        }
    }
}

struct RSSBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

private struct ArticleReaderView: View {
    let article: RSSArticle
    @ObservedObject var store: RSSStore
    @Environment(\.dismiss) private var dismiss
    @State private var showOriginal = false
    private var content: ArticleContent? { store.articleContents[article.id] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(content?.title.isEmpty == false ? content!.title : article.title)
                        .font(.title.bold()).accessibilityIdentifier("readerTitle")
                    HStack {
                        Text(store.feeds.first(where: { $0.url == article.feedURL })?.title ?? article.url?.host ?? "")
                        if let date = article.date { Text(date, style: .date) }
                    }.font(.caption).foregroundStyle(.secondary)
                    if let author = content?.author, !author.isEmpty { Text(author).font(.subheadline).foregroundStyle(.secondary) }
                    if let content {
                        ForEach(Array(content.blocks.enumerated()), id: \.offset) { _, block in
                            readerBlock(block)
                        }
                        Text("端末に保存した記事を表示しています。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        if !article.summary.isEmpty { Text(article.summary).font(.body).lineSpacing(6) }
                        Text(store.contentErrors[article.id] != nil
                             ? "本文を先読みできなかったため、保存済みの要約を表示しています。"
                             : store.contentPendingCount > 0
                             ? "本文を先読み中です。現在は保存済みの要約を表示しています。"
                             : "保存済みの要約を表示しています。本文は更新時に新しい記事から先読みします。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
            }
            .navigationTitle("記事")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: article.id) {
                // Let the sheet finish presenting before removing its row from the unread list.
                do { try await Task.sleep(for: .milliseconds(650)) }
                catch { return }
                guard !Task.isCancelled else { return }
                store.setRead(true, articles: [article])
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if article.url != nil {
                        Button { showOriginal = true } label: { Label("元の記事を開く", systemImage: "safari") }
                    }
                }
            }
            .sheet(isPresented: $showOriginal) {
                if let url = article.url { RSSBrowser(url: url).ignoresSafeArea() }
            }
        }
    }

    @ViewBuilder
    private func readerBlock(_ block: ArticleContent.Block) -> some View {
        switch block.kind {
        case .heading: Text(block.text).font(.title2.bold())
        case .paragraph: Text(block.text).font(.body).lineSpacing(6)
        case .listItem: HStack(alignment: .top) { Text("•"); Text(block.text).lineSpacing(5) }
        case .quote: Text(block.text).italic().foregroundStyle(.secondary).padding(.leading, 16)
        case .code: Text(block.text).font(.system(.footnote, design: .monospaced)).padding(12).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 8))
        case .image:
            if let data = block.imageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(block.text)
            } else if !block.text.isEmpty { Text(block.text).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
