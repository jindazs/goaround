import XCTest

final class goaroundUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testRSSNavigationAndInvalidFeedURL() throws {
        let app = XCUIApplication()
        app.launch()
        let rssTab = app.tabBars.buttons["RSS"]
        XCTAssertTrue(rssTab.waitForExistence(timeout: 10))
        rssTab.tap()
        app.buttons["RSSメニュー"].tap()
        app.buttons["フィード管理"].tap()
        let field = app.textFields["rssFeedURL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["OPMLをインポート"].exists)
        app.buttons["OPMLをインポート"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == 'キャンセル'")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("not-a-feed-url")
        app.buttons["追加"].tap()
        XCTAssertTrue(app.staticTexts["httpまたはhttpsのRSS/AtomフィードURLを入力してください。"].waitForExistence(timeout: 5))
        app.buttons["完了"].tap()
        XCTAssertFalse(app.switches["未読のみ"].exists)
        XCTAssertFalse(app.textFields["記事を検索"].exists)
        app.tabBars.buttons["ページ"].tap()
        XCTAssertTrue(app.tabBars.buttons["RSS"].exists)
    }

    func testWebsiteSourceControls() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["RSS"].tap()
        app.buttons["RSSメニュー"].tap()
        app.buttons["フィード管理"].tap()
        app.segmentedControls.buttons["Webサイト"].tap()
        XCTAssertTrue(app.textFields["rssFeedURL"].exists)
        app.buttons["自動抽出で見つからない場合"].tap()
        XCTAssertTrue(app.textFields["websiteLinkSelector"].waitForExistence(timeout: 5))
        app.buttons["完了"].tap()
    }

    func testReaderOpensSavedBodyWithoutWebViewAndControlsLiveInMenu() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-ui-fixture"]
        app.launch()
        app.tabBars.buttons["RSS"].tap()
        XCTAssertTrue(app.staticTexts["端末内で読める記事"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["未読のみ"].exists)
        XCTAssertFalse(app.textFields["rssSearchQuery"].exists)
        XCTAssertFalse(app.buttons["フィード管理"].exists)
        let front = XCTAttachment(screenshot: app.screenshot())
        front.name = "RSS front without filters"
        front.lifetime = .keepAlways
        add(front)
        app.buttons["RSSメニュー"].tap()
        XCTAssertTrue(app.buttons["フィード管理"].exists)
        app.buttons["記事を検索"].tap()
        let search = app.textFields["rssSearchQuery"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("端末内")
        app.buttons["適用"].tap()
        app.staticTexts["端末内で読める記事"].tap()
        XCTAssertTrue(app.staticTexts["保存済みの本文"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.webViews.count, 0)
        XCTAssertTrue(app.buttons["元の記事を開く"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Offline article reader"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testUnreadArticleIsMarkedReadAfterItsSheetAppears() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-ui-fixture"]
        app.launch()
        app.tabBars.buttons["RSS"].tap()
        app.buttons["RSSメニュー"].tap()
        app.buttons["未読のみ"].tap()
        let article = app.staticTexts["端末内で読める記事"]
        XCTAssertTrue(article.waitForExistence(timeout: 5))
        article.tap()
        XCTAssertTrue(app.staticTexts["保存済みの本文"].waitForExistence(timeout: 5))
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.staticTexts["記事がありません"].waitForExistence(timeout: 5))
    }

    func testMarkAllArticlesReadMenu() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-ui-fixture"]
        app.launch()
        app.tabBars.buttons["RSS"].tap()
        app.buttons["RSSメニュー"].tap()
        app.buttons["すべての記事を既読にする"].tap()
        app.buttons["RSSメニュー"].tap()
        app.buttons["未読のみ"].tap()
        XCTAssertTrue(app.staticTexts["記事がありません"].waitForExistence(timeout: 5))
    }

    func testScrollingPastAnArticleMarksItRead() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-ui-fixture", "--scroll-ui-fixture"]
        app.launch()
        app.tabBars.buttons["RSS"].tap()
        XCTAssertTrue(app.buttons["未読、スクロール記事 1"].waitForExistence(timeout: 5))
        app.swipeUp()
        let readAfterScroll = NSPredicate(format: "value != %@", "24件未読")
        expectation(for: readAfterScroll, evaluatedWith: app.buttons["RSSメニュー"])
        waitForExpectations(timeout: 8)
        app.swipeDown()
        XCTAssertTrue(app.buttons["既読、スクロール記事 1"].waitForExistence(timeout: 5))
    }

    func testUnreadOnlyScrollDoesNotMarkUnseenArticlesRead() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-ui-fixture", "--scroll-ui-fixture"]
        app.launch()
        app.tabBars.buttons["RSS"].tap()
        app.buttons["RSSメニュー"].tap()
        app.buttons["未読のみ"].tap()
        app.swipeUp()
        expectation(for: NSPredicate(format: "value != %@", "24件未読"), evaluatedWith: app.buttons["RSSメニュー"])
        waitForExpectations(timeout: 8)
        let value = app.buttons["RSSメニュー"].value as? String ?? ""
        let count = Int(value.replacingOccurrences(of: "件未読", with: "")) ?? 0
        XCTAssertGreaterThan(count, 0)
        XCTAssertLessThan(count, 24)
        app.swipeDown()
        XCTAssertFalse(app.buttons["未読、スクロール記事 1"].exists)
        XCTAssertFalse(app.staticTexts["記事がありません"].exists)
    }

    func testUnreadOnlyAutoReadKeepsRowsUntilFilterChanges() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-ui-fixture", "--scroll-ui-fixture"]
        app.launch()
        app.tabBars.buttons["RSS"].tap()
        app.buttons["RSSメニュー"].tap()
        app.buttons["未読のみ"].tap()
        app.swipeUp()
        expectation(for: NSPredicate(format: "value != %@", "24件未読"), evaluatedWith: app.buttons["RSSメニュー"])
        waitForExpectations(timeout: 8)

        let visibleRows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '未読、スクロール記事 '"))
            .allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertFalse(visibleRows.isEmpty)
        let positions = visibleRows.map { $0.frame.minY }
        let unreadCount = app.buttons["RSSメニュー"].value as? String
        // Give any delayed layout or automatic read work a chance to move the remaining rows.
        let settled = expectation(description: "List has settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        for (row, y) in zip(visibleRows, positions) {
            XCTAssertEqual(row.frame.minY, y, accuracy: 1)
        }
        XCTAssertEqual(app.buttons["RSSメニュー"].value as? String, unreadCount)

        app.swipeDown()
        XCTAssertTrue(app.buttons["既読、スクロール記事 1"].waitForExistence(timeout: 5),
                      "Automatically read rows must retain their space during browsing")
        app.buttons["RSSメニュー"].tap()
        app.buttons["未読のみ"].tap()
        app.buttons["RSSメニュー"].tap()
        app.buttons["未読のみ"].tap()
        XCTAssertFalse(app.buttons["既読、スクロール記事 1"].exists,
                       "Changing the filter must apply the current unread state")
    }

    func testBottomMarkAllReadButton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reader-ui-fixture", "--scroll-ui-fixture"]
        app.launch()
        app.tabBars.buttons["RSS"].tap()
        let bottom = app.buttons["rssBottomMarkAllRead"]
        for _ in 0..<10 {
            if bottom.exists && bottom.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(bottom.isHittable)
        bottom.tap()
        app.buttons["RSSメニュー"].tap()
        app.buttons["未読のみ"].tap()
        XCTAssertTrue(app.staticTexts["記事がありません"].waitForExistence(timeout: 5))
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
