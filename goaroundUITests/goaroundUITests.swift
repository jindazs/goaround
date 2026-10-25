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
        XCTAssertTrue(app.switches["未読のみ"].exists)
        app.tabBars.buttons["ページ"].tap()
        XCTAssertTrue(app.tabBars.buttons["RSS"].exists)
    }

    func testWebsiteSourceControls() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["RSS"].tap()
        app.buttons["フィード管理"].tap()
        app.segmentedControls.buttons["Webサイト"].tap()
        XCTAssertTrue(app.textFields["rssFeedURL"].exists)
        app.buttons["自動抽出で見つからない場合"].tap()
        XCTAssertTrue(app.textFields["websiteLinkSelector"].waitForExistence(timeout: 5))
        app.buttons["完了"].tap()
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
