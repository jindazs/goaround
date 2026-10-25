import Foundation
import CoreFoundation
import SwiftSoup
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import WebKit

struct ArticleContent: Codable, Equatable, Sendable {
    struct Block: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable { case paragraph, heading, quote, listItem, code, image }
        var kind: Kind
        var text: String
        var imageURL: URL? = nil
        var imageData: Data? = nil
    }
    var articleID: String
    var sourceURL: URL
    var title: String
    var author: String?
    var blocks: [Block]
    var fetchedAt = Date()
}

enum ArticleContentError: LocalizedError {
    case noBody
    var errorDescription: String? { "記事本文を取得できませんでした。保存済みの要約を表示します。" }
}

enum ArticleContentParser {
    static func parse(_ html: String, articleID: String, pageURL: URL) throws -> ArticleContent {
        guard html.utf8.count <= 5_000_000 else { throw RSSFailure.tooLarge }
        let document = try SwiftSoup.parse(html, pageURL.absoluteString)
        let title = try document.select("meta[property=og:title]").first()?.attr("content")
            ?? document.select("h1").first()?.text() ?? document.title()
        let author = try document.select("meta[name=author]").first()?.attr("content")
        try document.select("script, style, nav, footer, aside, form, iframe, button, noscript, [hidden], [aria-hidden=true], .related, .related-posts, .share, .social-share, .comments, .advertisement, [role=navigation]").remove()
        var root: Element?
        // Prefer article-specific bodies over wrappers containing related posts and navigation.
        for selector in ["[itemprop=articleBody], .article-body, .article-content, .entry-content, .post-content, .post-body", "article", "main, [role=main]", "body"] {
            let candidates = try document.select(selector).array()
            var bestScore = 0
            for candidate in candidates {
                let textCount = try candidate.text().count
                let linkCount = try candidate.select("a").array().reduce(0) { $0 + (try $1.text().count) }
                let score = textCount - linkCount * 2
                if score > bestScore, textCount >= 80 { bestScore = score; root = candidate }
            }
            if root != nil { break }
        }
        guard let root else { throw ArticleContentError.noBody }
        var blocks: [ArticleContent.Block] = []
        var textCount = 0
        var imageURLs = Set<URL>()
        for node in try root.select("h1, h2, h3, h4, p, li, blockquote, pre, img, figcaption").array() {
            guard blocks.count < 300, textCount < 100_000 else { break }
            let tag = node.tagName()
            if tag != "img", node.parents().array().contains(where: { $0 !== root && ["li", "blockquote", "pre"].contains($0.tagName()) }) { continue }
            if tag == "img" {
                let raw = try [node.attr("data-src"), node.attr("data-lazy-src"), node.attr("src")].first(where: { !$0.isEmpty }) ?? ""
                guard !raw.isEmpty, let absolute = URL(string: raw, relativeTo: pageURL)?.absoluteURL,
                      let url = try? RSSURLs.validated(absolute.absoluteString), imageURLs.insert(url).inserted,
                      imageURLs.count <= 4 else { continue }
                blocks.append(.init(kind: .image, text: try node.attr("alt"), imageURL: url))
                continue
            }
            let text = try node.text(trimAndNormaliseWhitespace: tag != "pre").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !(tag == "h1" && text == title) else { continue }
            let kind: ArticleContent.Block.Kind
            switch tag {
            case "h1", "h2", "h3", "h4": kind = .heading
            case "li": kind = .listItem
            case "blockquote": kind = .quote
            case "pre": kind = .code
            default: kind = .paragraph
            }
            let limited = String(text.prefix(100_000 - textCount))
            blocks.append(.init(kind: kind, text: limited))
            textCount += limited.count
        }
        if textCount < 80 {
            let text = try root.text()
            guard text.count >= 80 else { throw ArticleContentError.noBody }
            blocks = [.init(kind: .paragraph, text: String(text.prefix(100_000)))]
        }
        return ArticleContent(articleID: articleID, sourceURL: pageURL, title: String(title.prefix(500)), author: author, blocks: blocks)
    }
}

enum ArticleContentClient {
    static func fetch(_ article: RSSArticle, session: URLSession = .shared) async throws -> ArticleContent {
        guard let original = article.url else { throw ArticleContentError.noBody }
        let url = try RSSURLs.validated(original.absoluteString)
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await limitedData(request, maximum: 5_000_000, session: session)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RSSFailure.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        if let mime = response.mimeType, !["text/html", "application/xhtml+xml"].contains(mime.lowercased()) {
            throw ArticleContentError.noBody
        }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding((response.textEncodingName ?? "") as CFString)
        let encoding = cfEncoding == kCFStringEncodingInvalidId ? nil : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        guard let html = String(data: data, encoding: .utf8) ?? encoding.flatMap({ String(data: data, encoding: $0) })
                ?? String(data: data, encoding: .shiftJIS) ?? String(data: data, encoding: .japaneseEUC) else { throw WebsiteArticleError.unsupportedEncoding }
        var content: ArticleContent
        do { content = try ArticleContentParser.parse(html, articleID: article.id, pageURL: response.url ?? url) }
        catch ArticleContentError.noBody { content = try await ArticleBodyRenderer.fetch(article: article, url: response.url ?? url) }
        var imageBytes = 0
        for index in content.blocks.indices where content.blocks[index].kind == .image {
            try Task.checkCancellation()
            guard let imageURL = content.blocks[index].imageURL else { continue }
            do {
                var imageRequest = URLRequest(url: imageURL)
                imageRequest.timeoutInterval = 10
                let (data, response) = try await limitedData(imageRequest, maximum: 2_000_000, session: session)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      response.mimeType?.hasPrefix("image/") == true,
                      let image = thumbnail(data), imageBytes + image.count <= 1_000_000 else { continue }
                content.blocks[index].imageData = image
                imageBytes += image.count
            } catch is CancellationError { throw CancellationError() }
            catch { continue } // Text remains readable when an image cannot be prefetched.
        }
        return content
    }

    private static func limitedData(_ request: URLRequest, maximum: Int, session: URLSession) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard response.expectedContentLength <= Int64(maximum) else { throw RSSFailure.tooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximum else { throw RSSFailure.tooLarge }
            data.append(byte)
        }
        return (data, response)
    }

    private static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                 kCGImageSourceThumbnailMaxPixelSize: 1400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// Files live in Application Support so the OS does not evict an offline article on cache cleanup.
struct ArticleContentCache {
    var directory: URL?
    static var standard: Self {
        Self(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("ArticleContent", isDirectory: true))
    }
    private func file(_ id: String) -> URL? {
        let name = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent(name + ".json")
    }
    func load(_ article: RSSArticle) -> ArticleContent? {
        guard let url = file(article.id), let data = try? Data(contentsOf: url),
              let content = try? JSONDecoder().decode(ArticleContent.self, from: data),
              content.articleID == article.id else { return nil }
        return content
    }
    func save(_ content: ArticleContent) {
        guard let directory, let url = file(content.articleID), let data = try? JSONEncoder().encode(content) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
    func trim() {
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        let ordered = files.compactMap { url -> (URL, Date, Int)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }.sorted { $0.1 > $1.1 }
        var size = 0
        for (index, entry) in ordered.enumerated() {
            size += entry.2
            if index >= 300 || size > 150_000_000 { try? FileManager.default.removeItem(at: entry.0) }
        }
    }
    func removeAll() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
final class ArticleBodyRenderer: NSObject, WKNavigationDelegate {
    private var view: WKWebView?
    private var continuation: CheckedContinuation<ArticleContent, Error>?
    private var timeout: Task<Void, Never>?
    private var extraction: Task<Void, Never>?
    private var article: RSSArticle!
    private var url: URL!

    static func fetch(article: RSSArticle, url: URL, html: String? = nil) async throws -> ArticleContent {
        let renderer = ArticleBodyRenderer()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                renderer.continuation = continuation
                renderer.article = article
                renderer.url = url
                let config = WKWebViewConfiguration()
                config.websiteDataStore = .nonPersistent()
                let view = WKWebView(frame: .zero, configuration: config)
                renderer.view = view
                view.navigationDelegate = renderer
                renderer.timeout = Task { [weak renderer] in
                    try? await Task.sleep(nanoseconds: 25_000_000_000)
                    if !Task.isCancelled { renderer?.finish(.failure(URLError(.timedOut))) }
                }
                if let html { view.loadHTMLString(html, baseURL: url) }
                else { view.load(URLRequest(url: url)) }
            }
        } onCancel: { Task { @MainActor in renderer.finish(.failure(CancellationError())) } }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        extraction?.cancel()
        extraction = Task { [weak self] in
            for _ in 0..<3 {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let self, let view = self.view else { return }
                    let html = try await view.evaluateJavaScript("document.documentElement.outerHTML") as? String ?? ""
                    let content = try ArticleContentParser.parse(html, articleID: self.article.id, pageURL: view.url ?? self.url)
                    self.finish(.success(content))
                    return
                } catch is CancellationError { return }
                catch ArticleContentError.noBody { continue }
                catch { self?.finish(.failure(error)); return }
            }
            self?.finish(.failure(ArticleContentError.noBody))
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<ArticleContent, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        extraction?.cancel()
        view?.navigationDelegate = nil
        view?.stopLoading()
        view = nil
        continuation.resume(with: result)
    }
}
