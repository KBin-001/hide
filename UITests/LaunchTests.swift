import XCTest

final class LaunchTests: XCTestCase {
    func testFreshLaunchPINCalculatorAndBackground() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
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
        app.buttons["AC"].tap()
        for digit in pin { app.buttons[String(digit)].tap() }
        app.buttons["="].tap()
        XCTAssertTrue(app.navigationBars["App 管理"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["AC"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["App 管理"].exists)
    }
}
