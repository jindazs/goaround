//
//  goaroundTests.swift
//  goaroundTests
//
//  Created by Yuki Jin on 2024/07/13.
//

import XCTest
@testable import goaround

final class goaroundTests: XCTestCase {
    func testConfiguredSettingsKeepsLegacyOpenInAppAlignedWithURLRows() throws {
        let urls = ["", "https://x.com/i/lists/example", "https://example.com/comic"]
        let openInApp = [true, false, true]

        let settings = WebSiteSettingsStore.configuredSettings(
            settingsData: Data(),
            legacyWebSitesData: try encoded(urls),
            legacyOpenInAppData: try encoded(openInApp)
        )

        XCTAssertEqual(settings.map(\.url), ["https://x.com/i/lists/example", "https://example.com/comic"])
        XCTAssertEqual(settings.map(\.openInApp), [false, true])
    }

    func testEditableSettingsPadsWithUniqueRows() throws {
        let settings = WebSiteSettingsStore.editableSettings(
            settingsData: Data(),
            legacyWebSitesData: Data(),
            legacyOpenInAppData: Data()
        )

        XCTAssertEqual(settings.count, Constants.maxWebSites)
        XCTAssertEqual(Set(settings.map(\.id)).count, Constants.maxWebSites)
    }

    func testSavingNormalizesWhitespace() throws {
        let settings = [
            WebSiteSetting(url: "  https://example.com  ", openInApp: true)
        ]

        let normalized = WebSiteSettingsStore.normalizedForSaving(settings)

        XCTAssertEqual(normalized.first?.url, "https://example.com")
    }

    func testExportImportRoundTripsOpenInAppValues() throws {
        let settings = [
            WebSiteSetting(
                url: "https://x.com/i/lists/example",
                openInApp: false,
                hideXBottomMenu: true
            ),
            WebSiteSetting(url: "https://example.com/comic", openInApp: true)
        ]

        let data = try WebSiteSettingsTransfer.exportData(from: settings)
        let imported = try WebSiteSettingsTransfer.importedSettings(from: data)

        XCTAssertEqual(imported.map(\.url), settings.map(\.url))
        XCTAssertEqual(imported.map(\.openInApp), settings.map(\.openInApp))
        XCTAssertEqual(imported.map(\.hideXBottomMenu), [true, false])
    }

    func testOldSavedSettingsDefaultToShowingXBottomMenu() throws {
        let data = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","url":"https://x.com/home","openInApp":true}]"#.utf8)

        let settings = try JSONDecoder().decode([WebSiteSetting].self, from: data)

        XCTAssertEqual(settings.first?.hideXBottomMenu, false)
    }

    func testXSiteDetection() {
        XCTAssertTrue(WebSiteSetting(url: "x.com/home", openInApp: true).isXSite)
        XCTAssertTrue(WebSiteSetting(url: "https://mobile.x.com/home", openInApp: true).isXSite)
        XCTAssertFalse(WebSiteSetting(url: "https://example.com/?next=x.com", openInApp: true).isXSite)
    }

    func testImportPlainTextURLList() throws {
        let data = Data("""
        https://x.com/i/lists/example
        # comment
        https://example.com/comic
        """.utf8)

        let imported = try WebSiteSettingsTransfer.importedSettings(from: data)

        XCTAssertEqual(imported.map(\.url), ["https://x.com/i/lists/example", "https://example.com/comic"])
        XCTAssertEqual(imported.map(\.openInApp), [true, true])
    }

    func testCloudSyncTransfersOrderOptionsAndDeletion() throws {
        let cloud = MemoryCloudStore()
        let first = makeDefaults()
        let second = makeDefaults()
        let a = WebSiteSettingsSync(defaults: first, cloud: cloud)
        let b = WebSiteSettingsSync(defaults: second, cloud: cloud)
        let sites = [WebSiteSetting(url: "https://x.com", openInApp: false, hideXBottomMenu: true),
                     WebSiteSetting(url: "https://example.com", openInApp: true)]
        a.save(sites)
        b.reconcile()
        XCTAssertEqual(try loaded(second), sites)
        b.save(Array(sites.reversed()))
        a.reconcile()
        XCTAssertEqual(try loaded(first), Array(sites.reversed()))
        b.save([])
        a.reconcile()
        XCTAssertEqual(try loaded(first), [])
        XCTAssertTrue(WebSiteSettingsStore.configuredSettings(
            settingsData: first.data(forKey: WebSiteSettingsStore.settingsKey)!,
            legacyWebSitesData: try encoded(["stale"]), legacyOpenInAppData: Data()).isEmpty)
    }

    func testDelayedCloudDownloadWinsOverLegacyMigration() throws {
        let defaults = makeDefaults()
        defaults.set(try encoded(["https://old.example"]), forKey: WebSiteSettingsStore.legacyWebSitesKey)
        let cloud = MemoryCloudStore()
        let sync = WebSiteSettingsSync(defaults: defaults, cloud: cloud)
        sync.reconcile()
        XCTAssertNotNil(cloud.value)
        let remote = WebSiteSettingsSnapshot(modifiedAt: Date(), settings: [
            WebSiteSetting(url: "https://new.example", openInApp: false)
        ])
        cloud.value = try encoded(remote)
        sync.reconcile()
        XCTAssertEqual(try loaded(defaults), remote.settings)
    }

    func testNewDeviceDoesNotPublishEmptyList() {
        let cloud = MemoryCloudStore()
        WebSiteSettingsSync(defaults: makeDefaults(), cloud: cloud).reconcile()
        XCTAssertNil(cloud.value)
    }

    func testOlderRemoteDoesNotReplaceOfflineEdit() throws {
        let defaults = makeDefaults()
        let cloud = MemoryCloudStore()
        let sync = WebSiteSettingsSync(defaults: defaults, cloud: cloud)
        sync.save([WebSiteSetting(url: "https://new.example", openInApp: true)])
        let saved = try loaded(defaults)
        cloud.value = try encoded(WebSiteSettingsSnapshot(modifiedAt: .distantPast, settings: []))
        sync.reconcile()
        XCTAssertEqual(try loaded(defaults), saved)
        XCTAssertEqual(try JSONDecoder().decode(WebSiteSettingsSnapshot.self, from: cloud.value!).settings, saved)
    }

    func testInvalidRemotePreservesLocalSettings() throws {
        let defaults = makeDefaults()
        let sites = [WebSiteSetting(url: "https://example.com", openInApp: true)]
        defaults.set(try encoded(sites), forKey: WebSiteSettingsStore.settingsKey)
        let cloud = MemoryCloudStore()
        cloud.value = Data("invalid".utf8)
        WebSiteSettingsSync(defaults: defaults, cloud: cloud).reconcile()
        XCTAssertEqual(try loaded(defaults), sites)
        XCTAssertEqual(cloud.value, Data("invalid".utf8))
    }

    func testAccountChangeDoesNotUploadPreviousAccountList() throws {
        let defaults = makeDefaults()
        let cloud = MemoryCloudStore()
        let sync = WebSiteSettingsSync(defaults: defaults, cloud: cloud)
        sync.start()
        sync.save([WebSiteSetting(url: "https://private.example", openInApp: true)])
        cloud.value = nil
        NotificationCenter.default.post(name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                        object: cloud,
                                        userInfo: [NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreAccountChange])
        sync.refresh()
        XCTAssertNil(cloud.value)
        XCTAssertEqual(try loaded(defaults).count, 1)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "GoAroundTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func loaded(_ defaults: UserDefaults) throws -> [WebSiteSetting] {
        try JSONDecoder().decode([WebSiteSetting].self, from: XCTUnwrap(defaults.data(forKey: WebSiteSettingsStore.settingsKey)))
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }
}

private final class MemoryCloudStore: NSObject, SettingsCloudStore {
    var value: Data?
    func data(forKey key: String) -> Data? { value }
    func set(_ value: Data?, forKey key: String) { self.value = value }
    func synchronize() -> Bool { true }
}

final class RSSParserTests: XCTestCase {
    private let source = URL(string: "https://example.com/feed.xml")!

    func testRSSParsesCDATAStableGUIDDateAndLink() throws {
        let xml = """
        <rss version="2.0"><channel><title>Example &amp; News</title>
        <item><guid isPermaLink="false">stable-id</guid><title>First</title>
        <link>https://example.com/article#section</link>
        <description><![CDATA[<p>Hello &amp; world</p>]]></description>
        <pubDate>Sat, 24 Oct 2026 12:00:00 GMT</pubDate></item>
        </channel></rss>
        """
        let parsed = try RSSParser.parse(Data(xml.utf8), source: source)
        XCTAssertEqual(parsed.title, "Example & News")
        XCTAssertEqual(parsed.articles.count, 1)
        XCTAssertEqual(parsed.articles[0].summary, "Hello & world")
        XCTAssertEqual(parsed.articles[0].url?.fragment, "section")
        XCTAssertNotNil(parsed.articles[0].date)
        let edited = try RSSParser.parse(Data(xml.replacingOccurrences(of: "First", with: "Edited").utf8), source: source)
        XCTAssertEqual(edited.articles[0].id, parsed.articles[0].id)
    }

    func testAtomParsesAlternateLinkNestedSummaryAndDate() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Atom</title>
        <entry><id>urn:article:1</id><title>Entry</title>
        <link rel="self" href="/entry.atom"/><link rel="alternate" href="/entry"/>
        <updated>2026-10-24T12:30:00.123Z</updated>
        <summary type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml">Hello <b>world</b></div></summary>
        </entry></feed>
        """
        let parsed = try RSSParser.parse(Data(xml.utf8), source: source)
        XCTAssertEqual(parsed.articles[0].url?.absoluteString, "https://example.com/entry")
        XCTAssertEqual(parsed.articles[0].summary, "Hello world")
        XCTAssertNotNil(parsed.articles[0].date)
    }

    func testRejectsHTMLAndMalformedXMLAndUnsafeURLs() throws {
        XCTAssertThrowsError(try RSSParser.parse(Data("<html><body>Not a feed</body></html>".utf8), source: source))
        XCTAssertThrowsError(try RSSParser.parse(Data("<rss><channel>".utf8), source: source))
        XCTAssertThrowsError(try RSSURLs.validated("javascript:alert(1)"))
        XCTAssertThrowsError(try RSSURLs.validated("https://user:password@example.com/feed"))
        let parsed = try RSSParser.parse(Data("<rss><channel><item><title>No link</title></item></channel></rss>".utf8), source: source)
        XCTAssertNil(parsed.articles[0].url)
    }

    func testEmptyFeedAndDuplicateIDs() throws {
        XCTAssertTrue(try RSSParser.parse(Data("<feed/>".utf8), source: source).articles.isEmpty)
        let parsed = try RSSParser.parse(Data("<rss><channel><item><guid>1</guid><title>A</title></item><item><guid>1</guid><title>B</title></item></channel></rss>".utf8), source: source)
        XCTAssertEqual(parsed.articles.count, 1)
        XCTAssertNotEqual(RSSURLs.articleID(feed: "a", identifier: "1"), RSSURLs.articleID(feed: "b", identifier: "1"))
    }
}

final class RSSSyncTests: XCTestCase {
    func testOfflineChangesMergeAndDeletionWinsWithoutLosingOtherReads() {
        let old = Date(timeIntervalSince1970: 100)
        let new = Date(timeIntervalSince1970: 200)
        let feed = RSSFeed(url: "https://example.com/feed", title: "Example")
        var a = RSSSyncState()
        a.feeds[feed.url] = RSSChange(value: feed, date: old)
        a.reads["article-a"] = RSSChange(value: true, date: old)
        var b = RSSSyncState()
        b.feeds[feed.url] = RSSChange(value: nil, date: new)
        b.reads["article-b"] = RSSChange(value: true, date: new)
        b.reads["article-a"] = RSSChange(value: false, date: new)
        var mergedA = a
        mergedA.merge(b)
        var mergedB = b
        mergedB.merge(a)
        XCTAssertEqual(mergedA, mergedB)
        XCTAssertNil(mergedA.feeds[feed.url]?.value)
        XCTAssertEqual(mergedA.reads["article-a"]?.value, false)
        XCTAssertEqual(mergedA.reads["article-b"]?.value, true)
    }

    func testCompactionCannotRestoreExpiredReadHistoryFromOfflineDevice() {
        var state = RSSSyncState()
        for index in 1...1005 {
            state.reads[String(index)] = RSSChange(value: true, date: Date(timeIntervalSince1970: Double(index)))
        }
        let stale = state
        state.compact()
        XCTAssertEqual(state.reads.count, 1000)
        XCTAssertNil(state.reads["1"])
        state.merge(stale)
        XCTAssertEqual(state.reads.count, 1000)
        XCTAssertNil(state.reads["1"])
    }

    func testSameTimestampConflictConverges() {
        let date = Date()
        var a = RSSSyncState()
        var b = RSSSyncState()
        a.reads["article"] = RSSChange(value: true, date: date, revision: "a")
        b.reads["article"] = RSSChange(value: false, date: date, revision: "b")
        var result = a
        result.merge(b)
        b.merge(a)
        XCTAssertEqual(result, b)
        XCTAssertEqual(result.reads["article"]?.value, false)
    }

    @MainActor
    func testStoresPersistSyncAndIsolateAccountChanges() throws {
        let name = "RSSTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let cloud = MemoryCloudStore()
        var remote = RSSSyncState()
        let feed = RSSFeed(url: "https://example.com/feed", title: "Example")
        remote.feeds[feed.url] = RSSChange(value: feed, date: Date())
        cloud.value = try JSONEncoder().encode(remote)
        let store = RSSStore(defaults: defaults, cloud: cloud, cacheURL: nil)
        store.reconcile()
        XCTAssertEqual(store.feeds, [feed])
        let article = RSSArticle(id: "a", feedURL: feed.url, title: "A", summary: "")
        store.setRead(true, articles: [article])
        XCTAssertTrue(store.isRead(article))
        let restored = RSSStore(defaults: defaults, cloud: cloud, cacheURL: nil)
        XCTAssertTrue(restored.isRead(article))
        var pending = try JSONDecoder().decode(RSSSyncState.self, from: XCTUnwrap(cloud.value))
        pending.reads["another-device"] = RSSChange(value: true, date: Date())
        cloud.value = try JSONEncoder().encode(pending)
        store.setRead(false, articles: [article])
        XCTAssertEqual(store.state.reads["another-device"]?.value, true)
        XCTAssertFalse(store.isRead(article))
        store.removeFeed(feed)
        restored.reconcile()
        XCTAssertTrue(restored.feeds.isEmpty)
        cloud.value = nil
        store.cloudChanged(reason: NSUbiquitousKeyValueStoreAccountChange)
        store.reconcile()
        XCTAssertTrue(store.feeds.isEmpty)
        XCTAssertFalse(store.isRead(article))
        XCTAssertNil(cloud.value)
    }
}

final class OPMLImportTests: XCTestCase {
    func testNestedFoldersTitlesDuplicatesAndInvalidURLs() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0"><head><title>Subscriptions</title></head><body>
        <outline text="Folder"><outline text="News &amp; Updates" xmlUrl="https://EXAMPLE.com/feed#top"/>
        <outline text="Nested"><outline title="Atom title" text="Fallback" xmlUrl="https://example.org/atom"/></outline></outline>
        <outline xmlUrl="https://example.com/feed"/>
        <outline xmlUrl="javascript:alert(1)"/><outline type="rss" text="Missing URL"/>
        <outline text="Website only" htmlUrl="https://example.net"/>
        </body></opml>
        """
        let result = try OPMLParser.parse(Data(xml.utf8))
        XCTAssertEqual(result.feeds.map(\.url), ["https://example.com/feed", "https://example.org/atom"])
        XCTAssertEqual(result.feeds.map(\.title), ["News & Updates", "Atom title"])
        XCTAssertEqual(result.duplicates, 1)
        XCTAssertEqual(result.invalid, 2)
    }

    func testOPML1UTF16AndTitleFallback() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-16"?><opml version="1.0"><body>
        <outline text="日本語フィード" xmlUrl="https://example.com/jp"/>
        <outline title=" " text=" " xmlUrl="https://example.org/feed"/>
        </body></opml>
        """
        let result = try OPMLParser.parse(XCTUnwrap(xml.data(using: .utf16)))
        XCTAssertEqual(result.feeds.map(\.title), ["日本語フィード", "example.org"])
    }

    func testRejectsMalformedNonOPMLEmptyAndEntityDocuments() {
        for xml in ["<html/>", "<opml><body><outline xmlUrl='https://example.com/feed'/>",
                    "<opml><body/></opml>",
                    "<!DOCTYPE opml [<!ENTITY sample 'expanded'>]><opml><body><outline text='&sample;' xmlUrl='https://example.com/feed'/></body></opml>"] {
            XCTAssertThrowsError(try OPMLParser.parse(Data(xml.utf8)), xml)
        }
        XCTAssertThrowsError(try OPMLParser.parse(Data(repeating: 32, count: OPMLParser.maxBytes + 1)))
    }

    @MainActor
    func testImportPreservesExistingFeedsReadsAndPublishesOffline() throws {
        let name = "OPMLTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let cloud = MemoryCloudStore()
        var initial = RSSSyncState()
        let existing = RSSFeed(url: "https://example.com/feed", title: "Keep title")
        initial.feeds[existing.url] = RSSChange(value: existing, date: Date())
        initial.reads["article"] = RSSChange(value: true, date: Date())
        cloud.value = try JSONEncoder().encode(initial)
        let store = RSSStore(defaults: defaults, cloud: cloud, cacheURL: nil)
        let xml = Data("<opml><body><outline text='Changed title' xmlUrl='https://example.com/feed'/><outline text='New' xmlUrl='https://example.org/atom'/></body></opml>".utf8)
        let result = try store.importOPML(xml)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.duplicates, 1)
        XCTAssertEqual(store.state.feeds[existing.url]?.value?.title, "Keep title")
        XCTAssertEqual(store.state.reads["article"]?.value, true)
        let published = try JSONDecoder().decode(RSSSyncState.self, from: XCTUnwrap(cloud.value))
        XCTAssertEqual(published.feeds.values.compactMap(\.value).count, 2)
        XCTAssertEqual(RSSStore(defaults: defaults, cloud: cloud, cacheURL: nil).feeds.count, 2)
        let again = try store.importOPML(xml)
        XCTAssertEqual(again.added, 0)
        XCTAssertEqual(again.duplicates, 2)
        let before = store.state
        XCTAssertThrowsError(try store.importOPML(Data("<opml><body>".utf8)))
        XCTAssertEqual(store.state, before)
    }

    @MainActor
    func testImportReportsLimitWithoutDroppingExistingFeeds() throws {
        let name = "OPMLLimitTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let cloud = MemoryCloudStore()
        let store = RSSStore(defaults: defaults, cloud: cloud, cacheURL: nil)
        let outlines = (0..<102).map { "<outline text='Feed \($0)' xmlUrl='https://example.com/feed/\($0)'/>" }.joined()
        let result = try store.importOPML(Data("<opml><body>\(outlines)</body></opml>".utf8))
        XCTAssertEqual(result.added, 100)
        XCTAssertEqual(result.overLimit, 2)
        XCTAssertEqual(store.feeds.count, 100)
        let removed = try XCTUnwrap(store.feeds.first)
        store.removeFeed(removed)
        let reimported = try store.importOPML(Data("<opml><body><outline xmlUrl='\(removed.url)'/></body></opml>".utf8))
        XCTAssertEqual(reimported.added, 1)
        XCTAssertEqual(store.feeds.count, 100)
    }
}
