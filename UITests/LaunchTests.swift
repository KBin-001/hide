import XCTest

final class LaunchTests: XCTestCase {
    func testPINReentryAndExitWhileRestoreIsSlow() throws {
        continueAfterFailure = false
        executionTimeAllowance = 150
        let app = XCUIApplication()
        app.launchEnvironment["CALCULATOR_TEST_SLOW_MANAGED_SETTINGS"] = "1"
        app.launchArguments += ["-family-controls.previous-approval", "YES"]
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
        let previousGrant = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "此前已授权，待确认")).firstMatch
        XCTAssertTrue(previousGrant.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["连接系统授权"].isEnabled,
                      "Previous approval must leave the cold-launch connection available for a manual attempt")
        XCTAssertFalse(app.buttons["系统选择器（上锁）"].isEnabled,
                       "A previous grant must not unlock app selection until iOS confirms it in this process")

        XCTAssertTrue(app.buttons["选择 App"].isEnabled,
                      "The catalog can be browsed without granting authority to hide apps")
        app.buttons["选择 App"].tap()
        XCTAssertTrue(app.navigationBars["选择 App"].waitForExistence(timeout: 5))
        capture(app, name: "Catalog-graphite")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("WeChat")
        let wechat = app.buttons["catalog.app.com.tencent.xin"]
        XCTAssertTrue(wechat.waitForExistence(timeout: 5))
        let saveCatalog = app.buttons["catalog.save"]
        XCTAssertTrue(saveCatalog.waitForExistence(timeout: 5),
                      "The bottom save action must remain visible while searching")
        XCTAssertFalse(saveCatalog.isEnabled, "No apps should be selected on opening the catalog")
        wechat.tap()
        let catalogReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true"), object: saveCatalog)
        XCTAssertEqual(XCTWaiter.wait(for: [catalogReady], timeout: 5), .completed,
                       "Selecting WeChat must enable the catalog save action")
        saveCatalog.tap()
        XCTAssertTrue(app.navigationBars["App 管理"].waitForExistence(timeout: 5))
        capture(app, name: "Management-graphite")

        let restore = app.buttons["management.restore"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: restore)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        app.descendants(matching: .any)["诊断"].firstMatch.tap()
        let export = app.buttons["导出诊断日志"]
        let exportVisible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: export)
        XCTAssertEqual(XCTWaiter.wait(for: [exportVisible], timeout: 5), .completed,
                       "Opening diagnostics must reveal the export action")
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
        app.buttons["更改 PIN"].tap()
        let editor = app.navigationBars["更改 PIN"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        capture(app, name: "PIN-editor-graphite")
        let newPIN = String(Int.random(in: 1000...9999))
        let current = fields["当前 PIN"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        current.tap()
        current.typeText(pin)
        fields["新 PIN"].tap()
        fields["新 PIN"].typeText(newPIN)
        fields["再次输入"].tap()
        fields["再次输入"].typeText(newPIN)
        app.buttons["保存到 Keychain"].tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed, "Saving must dismiss the PIN editor")
        app.buttons["退出"].tap()
        submitPIN(app, pin: pin)
        XCTAssertTrue(app.staticTexts["结果 \(pin)"].exists)
        enterManagement(app, pin: newPIN)
        restore.tap()
        app.buttons["确认恢复全部"].tap()
        XCTAssertTrue(app.buttons["AC"].waitForExistence(timeout: 5))
    }

    private func enterManagement(_ app: XCUIApplication, pin: String) {
        submitPIN(app, pin: pin)
        XCTAssertTrue(app.navigationBars["App 管理"].waitForExistence(timeout: 10))
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func submitPIN(_ app: XCUIApplication, pin: String) {
        XCTAssertTrue(app.buttons["AC"].waitForExistence(timeout: 10))
        app.buttons["AC"].tap()
        for digit in pin { app.buttons[String(digit)].tap() }
        app.buttons["="].tap()
    }
}
