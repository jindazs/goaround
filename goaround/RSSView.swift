import SwiftUI
import SafariServices
import UniformTypeIdentifiers

struct RSSView: View {
    @ObservedObject private var store = RSSStore.shared
    @State private var unreadOnly = false
    @State private var selectedFeed = ""
    @State private var search = ""
    @State private var showFeeds = false
    @State private var selectedArticle: RSSArticle?

    private var visibleArticles: [RSSArticle] {
        store.articles.filter {
            (selectedFeed.isEmpty || $0.feedURL == selectedFeed) &&
            (!unreadOnly || !store.isRead($0)) &&
            (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.summary.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("フィード", selection: $selectedFeed) {
                        Text("すべてのフィード").tag("")
                        ForEach(store.feeds) { Text($0.title).tag($0.url) }
                    }
                    Toggle("未読のみ", isOn: $unreadOnly)
                }
                if store.isRefreshing {
                    HStack { ProgressView(); Text("フィードを更新中…").foregroundStyle(.secondary) }
                }
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
                        Text("RSS/AtomのURLを追加すると、ここで記事を読めます。")
                    } actions: {
                        Button("フィードを追加") { showFeeds = true }
                    }
                } else if visibleArticles.isEmpty, !store.isRefreshing {
                    ContentUnavailableView("記事がありません", systemImage: "tray", description: Text("表示条件を変更するか、下に引いて更新してください。"))
                }
                ForEach(visibleArticles) { article in
                    Button {
                        selectedArticle = article
                        store.setRead(true, articles: [article])
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
                            store.setRead(!store.isRead(article), articles: [article])
                        }.tint(.blue)
                    }
                    .accessibilityLabel("\(store.isRead(article) ? "既読" : "未読")、\(article.title)")
                }
            }
            .navigationTitle("RSS")
            .searchable(text: $search, prompt: "記事を検索")
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showFeeds = true } label: { Label("フィード管理", systemImage: "list.bullet") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("更新", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                        Button("表示中の記事をすべて既読にする", systemImage: "checkmark.circle") {
                            store.setRead(true, articles: visibleArticles)
                        }.disabled(visibleArticles.isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showFeeds) { RSSFeedsView(store: store) }
            .sheet(item: $selectedArticle) { article in
                if let url = article.url {
                    RSSBrowser(url: url).ignoresSafeArea()
                } else {
                    NavigationStack {
                        ScrollView { VStack(alignment: .leading, spacing: 16) {
                            Text(article.title).font(.title2.bold())
                            Text(article.summary)
                        }.padding() }
                        .toolbar { Button("閉じる") { selectedArticle = nil } }
                    }
                }
            }
            .task(id: store.feeds.map(\.url)) { await store.refresh() }
            .onChange(of: store.feeds) { _, feeds in
                if !feeds.contains(where: { $0.url == selectedFeed }) { selectedFeed = "" }
            }
        }
    }
}

private struct RSSFeedsView: View {
    @ObservedObject var store: RSSStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var isAdding = false
    @State private var error: String?
    @State private var pendingDeletion: RSSFeed?
    @State private var isImportingOPML = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("RSS / Atomフィードを追加") {
                    TextField("https://example.com/feed.xml", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("rssFeedURL")
                    Button {
                        isAdding = true
                        error = nil
                        Task {
                            defer { isAdding = false }
                            do { try await store.addFeed(url); url = "" }
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
                            Text(feed.title)
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

private struct RSSBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
