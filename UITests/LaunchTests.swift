import XCTest

final class LaunchTests: XCTestCase {
    func testPINReentryAndExitWhileRestoreIsSlow() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["CALCULATOR_TEST_SLOW_MANAGED_SETTINGS"] = "1"
        app.launch()
        defer {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Launch-screen"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertTrue(app.buttons["保存到 Keychain"].waitForExistence(timeout: 20),
                      "Fresh installation must show PIN setup, never a black screen")
        let pin = String(Int.random(in: 100000...999999))
        let fields = app.secureTextFields
        fields.element(boundBy: 0).tap()
        fields.element(boundBy: 0).typeText(pin)
        fields.element(boundBy: 1).tap()
        fields.element(boundBy: 1).typeText(pin)
        app.buttons["保存到 Keychain"].tap()
        XCTAssertTrue(app.buttons["AC"].waitForExistence(timeout: 10))
        app.buttons["7"].tap(); app.buttons["+"].tap(); app.buttons["3"].tap(); app.buttons["="].tap()
        XCTAssertTrue(app.staticTexts["结果 10"].exists)
        enterManagement(app, pin: pin)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["AC"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["App 管理"].exists)
        enterManagement(app, pin: pin)

        app.terminate()
        app.launch()
        enterManagement(app, pin: pin)

        let restore = app.buttons["management.restore"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: restore)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        app.descendants(matching: .any)["诊断"].firstMatch.tap()
        let export = app.buttons["导出诊断日志"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        restore.tap()
        app.buttons["确认恢复全部"].tap()
        XCTAssertTrue(app.staticTexts["系统处理较慢。仍可退出或导出日志。"].waitForExistence(timeout: 12))
        XCTAssertFalse(restore.isEnabled, "A pending request must prevent duplicate submissions")
        XCTAssertTrue(export.isEnabled)
        app.buttons["退出"].tap()
        XCTAssertTrue(app.buttons["AC"].waitForExistence(timeout: 5))
        enterManagement(app, pin: pin)

        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: restore)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 30), .completed,
                       "The late result must not close the management page opened after it started")
        restore.tap()
        app.buttons["确认恢复全部"].tap()
        XCTAssertTrue(app.buttons["AC"].waitForExistence(timeout: 5))
    }

    private func enterManagement(_ app: XCUIApplication, pin: String) {
        XCTAssertTrue(app.buttons["AC"].waitForExistence(timeout: 10))
        app.buttons["AC"].tap()
        for digit in pin { app.buttons[String(digit)].tap() }
        app.buttons["="].tap()
        XCTAssertTrue(app.navigationBars["App 管理"].waitForExistence(timeout: 10))
    }
}
