import Foundation
import CoreFoundation
import SwiftSoup
import WebKit

enum WebsiteArticleError: LocalizedError {
    case noArticles, invalidSelector, unsupportedEncoding
    var errorDescription: String? {
        switch self {
        case .noArticles: return "記事リンクを見つけられませんでした。記事一覧のURLを指定するか、記事リンクのCSSセレクタを設定してください。ログインが必要なサイトには対応していません。"
        case .invalidSelector: return "記事リンクのCSSセレクタを確認してください。例：article h2 a"
        case .unsupportedEncoding: return "ページの文字コードを読み取れませんでした。"
        }
    }
}

/// Extracts public article links from structured data and semantic HTML, without executing scripts.
enum WebsiteArticleParser {
    static func parse(_ html: String, pageURL: URL, sourceURL: URL, selector: String? = nil) throws -> RSSParsedFeed {
        guard html.utf8.count <= 5_000_000 else { throw RSSFailure.tooLarge }
        let document = try SwiftSoup.parse(html, pageURL.absoluteString)
        let title = try document.select("meta[property=og:site_name]").first()?.attr("content")
        let pageTitle = try document.title()
        let heading = String((title?.isEmpty == false ? title! : pageTitle.isEmpty ? (sourceURL.host ?? "Webサイト") : pageTitle).prefix(200))
        var result: [RSSArticle] = []
        var indices: [String: Int] = [:]

        func articleURL(_ raw: String) -> URL? {
            let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, !raw.hasPrefix("#"),
                  let absolute = URL(string: raw, relativeTo: pageURL)?.absoluteURL,
                  let url = try? RSSURLs.validated(absolute.absoluteString, removeFragment: true) else { return nil }
            func host(_ url: URL) -> String { (url.host ?? "").lowercased().replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression) }
            guard host(url) == host(pageURL), url.absoluteString != pageURL.absoluteString,
                  url.path != "/", !url.path.isEmpty else { return nil }
            let excluded = Set(["jpg", "jpeg", "png", "gif", "webp", "svg", "pdf", "zip", "mp4", "xml", "rss"])
            guard !excluded.contains(url.pathExtension.lowercased()),
                  url.path.range(of: "/(tags?|category|categories|login|signup|privacy|terms|contact|search)(/|$)", options: .regularExpression) == nil else { return nil }
            // Tracking query parameters should not create a different unread article on every refresh.
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            parts.queryItems = parts.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && !["fbclid", "gclid"].contains($0.name.lowercased()) }
            if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
            return parts.url
        }

        func append(title: String, link: String, summary: String = "", date: String? = nil) {
            let title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count >= 3, !["続きを読む", "もっと読む", "read more", "more", "詳細", "次へ", "前へ"].contains(title.lowercased()),
                  let url = articleURL(link) else { return }
            let id = RSSURLs.articleID(feed: sourceURL.absoluteString, identifier: url.absoluteString)
            let parsedDate = date.flatMap { RSSParser.date($0) }
            if let index = indices[id] {
                if result[index].date == nil { result[index].date = parsedDate }
                if result[index].summary.isEmpty { result[index].summary = String(summary.prefix(1000)) }
                return
            }
            guard result.count < 200 else { return }
            indices[id] = result.count
            result.append(RSSArticle(id: id, feedURL: sourceURL.absoluteString, title: String(title.prefix(500)),
                                     url: url, summary: String(summary.prefix(1000)), date: parsedDate))
        }

        let custom = selector?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if custom.isEmpty {
            // JSON-LD often contains publication dates even when visible cards omit them.
            func visit(_ value: Any, depth: Int = 0, inList: Bool = false) {
                guard depth < 30 else { return }
                if let array = value as? [Any] {
                    for child in array { visit(child, depth: depth + 1, inList: inList) }
                } else if let object = value as? [String: Any] {
                    let types = (object["@type"] as? [String]) ?? [object["@type"] as? String ?? ""]
                    guard !types.contains("BreadcrumbList") else { return }
                    let isArticle = types.contains { ["Article", "NewsArticle", "BlogPosting", "TechArticle", "Report"].contains($0) }
                    if isArticle || inList {
                        let link = object["url"] as? String ?? (object["mainEntityOfPage"] as? [String: Any])?["@id"] as? String ?? ""
                        append(title: object["headline"] as? String ?? object["name"] as? String ?? "", link: link,
                               summary: object["description"] as? String ?? "", date: object["datePublished"] as? String)
                    }
                    for (key, child) in object where child is [Any] || child is [String: Any] {
                        visit(child, depth: depth + 1, inList: (key == "itemListElement" && types.contains("ItemList")) || (inList && key == "item"))
                    }
                }
            }
            for script in try document.select("script[type=application/ld+json]").array() {
                if let data = try script.html().data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) { visit(json) }
            }
        }

        // Remove navigation and auxiliary links before selecting candidates.
        try document.select("nav, body > header, header[role=banner], footer, aside, script, style, form, [role=navigation]").remove()
        func addLink(_ link: Element, context: Element?) throws {
            let text = try link.text()
            let generic = ["続きを読む", "もっと読む", "read more", "more", "詳細"].contains(text.lowercased())
            let contextualTitle = try context?.select("[itemprop=headline], [class*=title], h1, h2, h3, h4").first()?.text() ?? ""
            let label = (text.isEmpty || generic) && !contextualTitle.isEmpty ? contextualTitle : text.isEmpty ? try link.attr("aria-label") : text
            let time = try context?.select("time[datetime]").first()?.attr("datetime")
            let summary = try context?.select("p").first()?.text() ?? ""
            append(title: label, link: try link.attr("href"), summary: summary, date: time)
        }
        if !custom.isEmpty {
            let selected: Elements
            do { selected = try document.select(custom) }
            catch { throw WebsiteArticleError.invalidSelector }
            for element in selected.array() {
                let links = element.tagName() == "a" ? [element] : try element.select("a[href]").array()
                for link in links { try addLink(link, context: link.parent()) }
            }
        } else {
            for card in try document.select("article, .post, .entry, .news-item, [class*=card], [itemtype$='/NewsArticle'], [itemtype$='/BlogPosting']").array() {
                let links = try card.select("h1 a[href], h2 a[href], h3 a[href], a[rel=bookmark], a[href]").array()
                // Card headings take priority over image-only links and category labels.
                let headingLink = try card.select("h1 a[href], h2 a[href], h3 a[href], a[rel=bookmark]").first()
                if let headingLink { try addLink(headingLink, context: card) }
                else if let link = links.first(where: { articleURL((try? $0.attr("href")) ?? "") != nil }) { try addLink(link, context: card) }
            }
            for link in try document.select("h2 a[href], h3 a[href], a[href]:has(h2), a[href]:has(h3)").array() {
                try addLink(link, context: link.parent()?.parent())
            }
            // Common article lists without semantic headings. Only plausible article paths qualify.
            for link in try document.select("main a[href], [class*=article] a[href], [class*=post] a[href], [class*=news] a[href]").array() {
                let path = try link.attr("href")
                if path.range(of: "/(20[0-9]{2}[/.-]|articles?/[^/]+|posts?/[^/]+|blog/[^/]+|news/[^/]+)", options: .regularExpression) != nil {
                    try addLink(link, context: link.parent())
                }
            }
        }
        guard !result.isEmpty else { throw WebsiteArticleError.noArticles }
        // Dates sort newest first; undated links retain their order on the source page.
        result = result.enumerated().sorted {
            let lhs = $0.element.date ?? .distantPast, rhs = $1.element.date ?? .distantPast
            return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
        }.map(\.element)
        return RSSParsedFeed(title: heading, articles: result)
    }
}

enum WebsiteArticleClient {
    static func fetch(_ url: URL, selector: String? = nil) async throws -> RSSParsedFeed {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RSSFailure.invalidFeed }
        guard (200..<300).contains(response.statusCode) else { throw RSSFailure.http(response.statusCode) }
        guard data.count <= 5_000_000 else { throw RSSFailure.tooLarge }
        let html: String
        if let utf8 = String(data: data, encoding: .utf8) { html = utf8 }
        else {
            let declared = response.textEncodingName ?? ""
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(declared as CFString)
            let declaredEncoding = cfEncoding == kCFStringEncodingInvalidId ? nil : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
            let decoded = declaredEncoding.flatMap { String(data: data, encoding: $0) }
                ?? String(data: data, encoding: .shiftJIS)
                ?? String(data: data, encoding: .japaneseEUC)
            guard let decoded else { throw WebsiteArticleError.unsupportedEncoding }
            html = decoded
        }
        let page = response.url ?? url
        do { return try WebsiteArticleParser.parse(html, pageURL: page, sourceURL: url, selector: selector) }
        catch WebsiteArticleError.noArticles {
            // Some sites populate article cards with JavaScript. Use an isolated, temporary browser.
            return try await WebsitePageRenderer.fetch(url, selector: selector)
        }
    }
}

@MainActor
final class WebsitePageRenderer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<RSSParsedFeed, Error>?
    private var timeout: Task<Void, Never>?
    private var extraction: Task<Void, Never>?
    private var source: URL!
    private var selector: String?

    static func fetch(_ url: URL, selector: String?, html: String? = nil) async throws -> RSSParsedFeed {
        let renderer = WebsitePageRenderer()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                renderer.continuation = continuation
                renderer.source = url
                renderer.selector = selector
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .nonPersistent()
                let view = WKWebView(frame: .zero, configuration: configuration)
                renderer.webView = view
                view.navigationDelegate = renderer
                renderer.timeout = Task { [weak renderer] in
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard !Task.isCancelled else { return }
                    renderer?.finish(.failure(URLError(.timedOut)))
                }
                if let html { view.loadHTMLString(html, baseURL: url) }
                else { view.load(URLRequest(url: url)) }
            }
        } onCancel: {
            Task { @MainActor in renderer.finish(.failure(CancellationError())) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        extraction?.cancel()
        extraction = Task { [weak self] in
            for _ in 0..<3 {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let self, let view = self.webView else { return }
                    let html = try await view.evaluateJavaScript("document.documentElement.outerHTML") as? String ?? ""
                    let parsed = try WebsiteArticleParser.parse(html, pageURL: view.url ?? self.source, sourceURL: self.source, selector: self.selector)
                    self.finish(.success(parsed))
                    return
                } catch is CancellationError { return }
                catch WebsiteArticleError.noArticles { continue }
                catch { self?.finish(.failure(error)); return }
            }
            self?.finish(.failure(WebsiteArticleError.noArticles))
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<RSSParsedFeed, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        extraction?.cancel()
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        continuation.resume(with: result)
    }
}
