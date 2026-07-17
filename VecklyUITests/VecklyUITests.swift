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
    func testHouseholdTabChangesLanguageAtRuntime() throws {
        let app = XCUIApplication()
        app.launchEnvironment["VECKLY_UI_TEST_MODE"] = "core-reader"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-veckly.app-language", "system"]
        app.launch()

        app.tabBars.buttons["Household"].tap()
        XCTAssertTrue(app.staticTexts["Test household"].waitForExistence(timeout: 5))

        app.buttons["languageSelectionLink"].tap()
        app.buttons["languageOption.swedish"].tap()

        XCTAssertTrue(app.tabBars.buttons["Hushåll"].waitForExistence(timeout: 5))
    }

    /// Fas 3: the hero and the planning-status card must agree with each
    /// other for a week that still has open planning days — the toolbar CTA
    /// copy is a secondary concern here, the content-area cards are what
    /// beslut 16/6 actually gate on.
    @MainActor
    func testWeekTabShowsOpenTonightHeroAndDaysLeftStatus() throws {
        let app = XCUIApplication()
        app.launchEnvironment["VECKLY_UI_TEST_MODE"] = "core-reader"
        app.launchEnvironment["VECKLY_UI_TEST_WEEK_SCENARIO"] = "openTonight"
        // Explicit, not relying on the simulator's ambient language or on
        // test run order — `testHouseholdTabChangesLanguageAtRuntime` really
        // taps the Swedish option, which persists `veckly.app-language` in
        // this app's UserDefaults for later launches too. `-AppleLanguages`
        // covers plain SwiftUI `Text(key)` lookups; `-veckly.app-language`
        // overrides the persisted in-app preference `L10n` reads for
        // everything routed through it (see `AppLocalePreference`).
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-veckly.app-language", "english"]
        app.launch()

        XCTAssertTrue(app.staticTexts["What's for dinner tonight?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Plan tonight"].exists)
        XCTAssertTrue(app.staticTexts["3 planning days left"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Plan the rest"].exists)
        XCTAssertFalse(app.staticTexts["The week is planned"].exists)
    }

    /// Fas 3: a fully planned week shows the closed-status card and the
    /// ordinary "tonight" hero — no open-days CTA anywhere on screen.
    @MainActor
    func testWeekTabShowsCompleteStatusWhenEveryPlanningDayIsFilled() throws {
        let app = XCUIApplication()
        app.launchEnvironment["VECKLY_UI_TEST_MODE"] = "core-reader"
        app.launchEnvironment["VECKLY_UI_TEST_WEEK_SCENARIO"] = "complete"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-veckly.app-language", "english"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Monday Pasta"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The week is planned"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open the shopping list"].exists)
        XCTAssertFalse(app.buttons["Plan the rest"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
