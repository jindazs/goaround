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

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }
}
