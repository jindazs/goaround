import Foundation
import CryptoKit

struct RSSFeed: Codable, Identifiable, Equatable {
    var id: String { url }
    var url: String
    var title: String
    // Optional fields preserve compatibility with existing RSS subscriptions and OPML imports.
    var sourceKind: String? = nil
    var linkSelector: String? = nil
    var isWebsite: Bool { sourceKind == "website" }
}

struct RSSArticle: Codable, Identifiable, Equatable {
    var id: String
    var feedURL: String
    var title: String
    var url: URL?
    var summary: String
    var date: Date?
}

struct RSSChange<Value: Codable & Equatable>: Codable, Equatable {
    var value: Value
    var date: Date
    var revision: String = UUID().uuidString

    func newer(than other: Self) -> Bool {
        date == other.date ? revision > other.revision : date > other.date
    }
}

struct RSSSyncState: Codable, Equatable {
    var version = 1
    // Deleted subscriptions remain as tombstones, so an offline device cannot resurrect them.
    var feeds: [String: RSSChange<RSSFeed?>] = [:]
    var reads: [String: RSSChange<Bool>] = [:]
    var readCutoff = Date.distantPast

    mutating func merge(_ other: Self) {
        feeds.merge(other.feeds) { $1.newer(than: $0) ? $1 : $0 }
        reads.merge(other.reads) { $1.newer(than: $0) ? $1 : $0 }
        readCutoff = max(readCutoff, other.readCutoff)
        compact()
    }

    mutating func compact() {
        reads = reads.filter { $0.value.date > readCutoff }
        let ordered = reads.sorted { $0.value.date > $1.value.date }
        if ordered.count > 1000 {
            readCutoff = max(readCutoff, ordered[1000].value.date)
            reads = reads.filter { $0.value.date > readCutoff }
        }
    }
}

enum RSSFailure: LocalizedError {
    case invalidURL, invalidFeed, tooLarge, http(Int), limit
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "httpまたはhttpsのRSS/AtomフィードURLを入力してください。"
        case .invalidFeed: return "RSS/Atomフィードを読み取れませんでした。フィードのURLを確認してください。"
        case .tooLarge: return "フィードのデータが大きすぎます。"
        case .http(let code): return "フィードの取得に失敗しました（HTTP \(code)）。"
        case .limit: return "登録できるフィードは100件までです。"
        }
    }
}

enum RSSURLs {
    static func validated(_ text: String, removeFragment: Bool = false) throws -> URL {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 2048, var parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else {
            throw RSSFailure.invalidURL
        }
        parts.scheme = scheme
        parts.host = host.lowercased()
        if removeFragment { parts.fragment = nil }
        guard let url = parts.url else { throw RSSFailure.invalidURL }
        return url
    }

    static func articleID(feed: String, identifier: String) -> String {
        SHA256.hash(data: Data((feed + "\n" + identifier).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct RSSParsedFeed {
    var title: String
    var articles: [RSSArticle]
}

/// RSS 2.0, RSS 1.0 (RDF), and Atom. External XML entities are never resolved.
final class RSSParser: NSObject, XMLParserDelegate {
    private let source: URL
    private var stack: [String] = []
    private var textStack: [String] = []
    private var fields: [String: String]?
    private var articleLink: String?
    private var title = ""
    private var articles: [RSSArticle] = []
    private var recognized = false

    init(source: URL) { self.source = source }

    static func parse(_ data: Data, source: URL) throws -> RSSParsedFeed {
        guard data.count <= 5_000_000 else { throw RSSFailure.tooLarge }
        let delegate = RSSParser(source: source)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.recognized else { throw RSSFailure.invalidFeed }
        return RSSParsedFeed(title: delegate.title.isEmpty ? (source.host ?? source.absoluteString) : delegate.title,
                             articles: delegate.articles)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        let name = elementName.components(separatedBy: ":").last!.lowercased()
        if stack.isEmpty { recognized = ["rss", "rdf", "feed"].contains(name) }
        guard stack.count < 64 else { parser.abortParsing(); return }
        stack.append(name)
        textStack.append("")
        if name == "item" || name == "entry" { fields = [:]; articleLink = nil }
        if fields != nil, name == "link", let href = attributes["href"],
           attributes["rel"] == nil || attributes["rel"] == "alternate" { articleLink = href }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !textStack.isEmpty { textStack[textStack.count - 1] += string }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let name = stack.popLast(), let raw = textStack.popLast() else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !textStack.isEmpty { textStack[textStack.count - 1] += raw }
        if name == "item" || name == "entry" {
            if let fields, articles.count < 200 {
                let link = articleLink ?? fields["link"] ?? ""
                let resolved = link.isEmpty ? nil : URL(string: link, relativeTo: source)?.absoluteURL
                let url = resolved.flatMap { try? RSSURLs.validated($0.absoluteString) }
                let heading = String(Self.plain(fields["title"] ?? "無題の記事").prefix(500))
                let identity = fields["guid"] ?? fields["id"] ?? url?.absoluteString ?? (heading + (fields["pubdate"] ?? fields["published"] ?? ""))
                let article = RSSArticle(id: RSSURLs.articleID(feed: source.absoluteString, identifier: identity),
                                         feedURL: source.absoluteString, title: heading, url: url,
                                         summary: String(Self.plain(fields["description"] ?? fields["summary"] ?? fields["encoded"] ?? fields["content"] ?? "").prefix(1000)),
                                         date: Self.date(fields["pubdate"] ?? fields["published"] ?? fields["updated"] ?? fields["date"] ?? ""))
                if !articles.contains(where: { $0.id == article.id }) { articles.append(article) }
            }
            fields = nil
        } else if fields != nil, ["item", "entry"].contains(stack.last ?? "") {
            fields?[name] = text
        } else if fields == nil, name == "title", ["channel", "feed"].contains(stack.last ?? "") {
            title = String(Self.plain(text).prefix(200))
        }
    }

    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func date(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

enum RSSClient {
    static func fetch(_ url: URL) async throws -> RSSParsedFeed {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RSSFailure.invalidFeed }
        guard (200..<300).contains(response.statusCode) else { throw RSSFailure.http(response.statusCode) }
        return try RSSParser.parse(data, source: url)
    }
}

struct OPMLImportResult {
    var feeds: [RSSFeed] = []
    var invalid = 0
    var duplicates = 0
    var added = 0
    var overLimit = 0

    var message: String {
        "\(added)件追加しました。\n重複：\(duplicates)件\n無効なURL：\(invalid)件\n登録上限によるスキップ：\(overLimit)件\n\n記事は登録後に取得します。フォルダ構成は取り込みません。"
    }
}

enum OPMLImportError: LocalizedError {
    case invalidDocument, tooLarge, noFeeds
    var errorDescription: String? {
        switch self {
        case .invalidDocument: return "OPMLファイルを読み取れませんでした。ファイルの形式を確認してください。"
        case .tooLarge: return "OPMLファイルは5MB以下にしてください。"
        case .noFeeds: return "取り込めるフィードがありません。xmlUrlを含むOPMLファイルを選んでください。"
        }
    }
}

/// Folder outlines are traversed recursively; only subscription xmlUrl attributes are imported.
final class OPMLParser: NSObject, XMLParserDelegate {
    static let maxBytes = 5_000_000
    private var stack: [String] = []
    private var hasRoot = false
    private var hasBody = false
    private var seen = Set<String>()
    private var result = OPMLImportResult()

    static func parse(_ data: Data) throws -> OPMLImportResult {
        guard data.count <= maxBytes else { throw OPMLImportError.tooLarge }
        let delegate = OPMLParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.hasRoot, delegate.hasBody else { throw OPMLImportError.invalidDocument }
        guard !delegate.result.feeds.isEmpty || delegate.result.invalid > 0 else { throw OPMLImportError.noFeeds }
        return delegate.result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        let name = elementName.lowercased()
        guard stack.count < 64 else { parser.abortParsing(); return }
        if stack.isEmpty {
            guard name == "opml" else { parser.abortParsing(); return }
            hasRoot = true
        }
        if stack == ["opml"], name == "body" { hasBody = true }
        stack.append(name)
        guard name == "outline", stack.starts(with: ["opml", "body"]),
              stack.dropFirst(2).allSatisfy({ $0 == "outline" }) else { return }
        var normalized: [String: String] = [:]
        for (key, value) in attributes { normalized[key.lowercased()] = value }
        guard let rawURL = normalized["xmlurl"] else {
            if normalized["type"]?.lowercased() == "rss" { result.invalid += 1 }
            return
        }
        guard let url = try? RSSURLs.validated(rawURL, removeFragment: true) else {
            result.invalid += 1
            return
        }
        guard seen.insert(url.absoluteString).inserted else { result.duplicates += 1; return }
        let title = [normalized["title"], normalized["text"]].compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first(where: { !$0.isEmpty })
        result.feeds.append(RSSFeed(url: url.absoluteString, title: String((title ?? url.host ?? url.absoluteString).prefix(200))))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = stack.popLast()
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
        parser.abortParsing()
    }
}
