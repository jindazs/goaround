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
