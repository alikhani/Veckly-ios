//
//  VecklyUITests.swift
//  VecklyUITests
//
//  Created by Nima on 2026-06-09.
//

import XCTest

final class VecklyUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testSignedOutScreenShowsAppleCTA() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Veckly"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Plan the week once. Know what's for dinner before the day starts."].exists)
        XCTAssertTrue(app.buttons["continueWithAppleButton"].exists)
    }

    @MainActor
    func testCoreReaderShowsWeekAndShoppingData() throws {
        let app = XCUIApplication()
        app.launchEnvironment["VECKLY_UI_TEST_MODE"] = "core-reader"
        app.launch()

        XCTAssertTrue(app.staticTexts["Monday Pasta"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Shopping"].tap()

        XCTAssertTrue(app.staticTexts["spaghetti"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSwedishLocaleUsesSwedishUI() throws {
        let app = XCUIApplication()
        app.launchEnvironment["VECKLY_UI_TEST_MODE"] = "core-reader"
        app.launchArguments += ["-AppleLanguages", "(sv)", "-AppleLocale", "sv_SE"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Den här veckan"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Handla"].tap()

        XCTAssertTrue(app.staticTexts["Inköpslista"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
