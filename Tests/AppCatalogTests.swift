import XCTest
@testable import CalculatorCore

final class AppCatalogTests: XCTestCase {
    func testRequestedAppsAndSearchAliases() throws {
        let expected = ["QQ": "com.tencent.mqq", "微信": "com.tencent.xin", "抖音": "com.ss.iphone.ugc.Aweme",
                        "小红书": "com.xingin.discover", "X": "com.atebits.Tweetie2",
                        "腾讯元宝": "com.tencent.hunyuan.app.chat", "ChatGPT": "com.openai.chat",
                        "AlipayHK": "com.alipay.wallethk", "台鐵e訂通": "tw.gov.tra.twtraffic",
                        "PayPay": "jp.pay2.app.ios"]
        for (name, id) in expected {
            XCTAssertEqual(AppCatalog.apps.first { $0.name == name }?.id, id)
        }
        XCTAssertTrue(try XCTUnwrap(AppCatalog.apps.first { $0.name == "微信" }).matches("wechat"))
        XCTAssertTrue(try XCTUnwrap(AppCatalog.apps.first { $0.name == "小红书" }).matches("XHS"))
        XCTAssertTrue(try XCTUnwrap(AppCatalog.apps.first { $0.name == "X" }).matches("twitter"))
        XCTAssertTrue(try XCTUnwrap(AppCatalog.apps.first { $0.name == "QQ音乐" }).matches("com.tencent.qqmusic"))
        XCTAssertFalse(try XCTUnwrap(AppCatalog.apps.first { $0.name == "QQ" }).matches("微信"))
    }

    func testCatalogIdentifiersAreUniqueAndBatchCanBeSavedWithoutRestrictions() throws {
        XCTAssertGreaterThanOrEqual(AppCatalog.apps.count, 484)
        XCTAssertEqual(Set(AppCatalog.apps.map { $0.id.lowercased() }).count, AppCatalog.apps.count)
        XCTAssertEqual(Set(AppCatalog.apps.map(\.category)), Set(AppCatalog.categories))
        var saves = 0
        var saved: Data?
        let p = BundleIDPolicy(ownBundleID: "com.personal.calculatorvault", load: { nil }, save: {
            saves += 1; saved = $0
        }, apply: { _ in XCTFail("Browsing and adding must never apply restrictions") })
        try p.addApps(AppCatalog.apps.map { (identifier: $0.id, name: $0.name) })
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(p.entries.count, AppCatalog.apps.count)
        XCTAssertTrue(p.entries.allSatisfy { $0.mode == .normal })
        let reopened = BundleIDPolicy(ownBundleID: "com.personal.calculatorvault", load: { saved }, save: { _ in },
                                     apply: { _ in XCTFail("Loading must not reapply restrictions") })
        XCTAssertEqual(reopened.entries.count, AppCatalog.apps.count)
    }

    func testInvalidBatchAndFailedSaveCannotLeavePartialSelection() throws {
        var saves = 0
        let p = BundleIDPolicy(ownBundleID: "com.personal.calculatorvault", load: { nil }, save: { _ in
            saves += 1
            throw CocoaError(.fileWriteNoPermission)
        }, apply: { _ in XCTFail("Adding must not apply restrictions") })
        XCTAssertThrowsError(try p.addApps([(identifier: "com.tencent.xin", name: "微信"),
                                         (identifier: "https://invalid", name: "Invalid")]))
        XCTAssertEqual(saves, 0)
        XCTAssertTrue(p.entries.isEmpty)
        XCTAssertThrowsError(try p.addApps([(identifier: "com.tencent.xin", name: "微信"),
                                         (identifier: "com.tencent.mqq", name: "QQ")]))
        XCTAssertEqual(saves, 1)
        XCTAssertTrue(p.entries.isEmpty)
    }
}
