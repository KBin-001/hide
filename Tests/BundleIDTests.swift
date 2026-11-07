import XCTest
@testable import CalculatorCore

final class BundleIDTests: XCTestCase {
    func testPersistReloadIsolateAndRemoveWithoutReapplyingOnLaunch() throws {
        var saved: Data?
        var writes: [Set<String>] = []
        func open() -> BundleIDPolicy {
            BundleIDPolicy(ownBundleID: "com.personal.calculatorvault", load: { saved }, save: { saved = $0 },
                           apply: { writes.append($0) })
        }
        let p = open()
        try p.add(identifier: " com.tencent.mqq ", name: " QQ ")
        try p.add(identifier: "com.example.second", name: "Second")
        let qq = try XCTUnwrap(p.entries.first { $0.token == "com.tencent.mqq" })
        let second = try XCTUnwrap(p.entries.first { $0.token == "com.example.second" })
        XCTAssertEqual(qq.nickname, "QQ")
        XCTAssertEqual(qq.mode, .normal)
        XCTAssertTrue(writes.isEmpty)
        try p.setHidden(true, id: qq.id)
        try p.setHidden(true, id: second.id)
        XCTAssertEqual(writes.last, ["com.tencent.mqq", "com.example.second"])
        let before = writes.count
        let reloaded = open()
        XCTAssertEqual(writes.count, before)
        XCTAssertEqual(reloaded.entries.first?.id, qq.id)
        XCTAssertEqual(reloaded.entries.first?.mode, .hidden)
        try reloaded.setHidden(false, id: qq.id)
        XCTAssertEqual(writes.last, ["com.example.second"])
        try reloaded.remove(id: second.id)
        XCTAssertEqual(writes.last, [])
        XCTAssertEqual(open().entries.count, 1)
        try reloaded.restoreAll()
        XCTAssertEqual(writes.last, [])
    }

    func testIdentifiersAndDuplicateDoNotOverwriteHiddenEntry() throws {
        let p = BundleIDPolicy(ownBundleID: "com.personal.calculatorvault", load: { nil }, save: { _ in }, apply: { _ in })
        for value in ["", "qq", "com..qq", "com.qq app", "com.qq/other", "com.你好.app", "COM.PERSONAL.CALCULATORVAULT"] {
            XCTAssertThrowsError(try p.add(identifier: value, name: ""), value)
        }
        try p.add(identifier: "com.tencent.mqq", name: "QQ")
        let id = try XCTUnwrap(p.entries.first?.id)
        try p.setHidden(true, id: id)
        try p.add(identifier: "com.tencent.mqq", name: "Duplicate")
        XCTAssertEqual(p.entries.count, 1)
        XCTAssertEqual(p.entries.first?.id, id)
        XCTAssertEqual(p.entries.first?.mode, .hidden)
        XCTAssertEqual(p.entries.first?.nickname, "QQ")
    }

    func testSaveFailureAndEmergencyRestore() throws {
        var fail = false
        var submitted: Set<String> = []
        let p = BundleIDPolicy(ownBundleID: "com.personal.calculatorvault", load: { nil }, save: { _ in
            if fail { throw CocoaError(.fileWriteNoPermission) }
        }, apply: { submitted = $0 })
        try p.add(identifier: "com.tencent.mqq", name: "QQ")
        let id = try XCTUnwrap(p.entries.first?.id)
        fail = true
        XCTAssertThrowsError(try p.setHidden(true, id: id))
        XCTAssertTrue(submitted.isEmpty)
        fail = false
        try p.setHidden(true, id: id)
        XCTAssertEqual(submitted, ["com.tencent.mqq"])
        fail = true
        XCTAssertThrowsError(try p.restoreAll())
        XCTAssertTrue(submitted.isEmpty, "Restore must clear system restrictions even if persistence fails")
        XCTAssertNotNil(p.loadError)
        fail = false
        try p.restoreAll()
        XCTAssertNil(p.loadError)
    }

    func testCombinedLimitIncludesPickerRestrictionsAndAllowsRecovery() throws {
        var pickerCount = 49
        var hidden: Set<String> = []
        let p = BundleIDPolicy(ownBundleID: "com.personal.calculatorvault", load: { nil }, save: { _ in },
                               otherRestrictedCount: { pickerCount }, apply: { hidden = $0 })
        try p.add(identifier: "com.tencent.mqq", name: "QQ")
        try p.add(identifier: "com.example.other", name: "Other")
        try p.setHidden(true, id: p.entries[0].id)
        XCTAssertThrowsError(try p.setHidden(true, id: p.entries[1].id))
        XCTAssertEqual(hidden, ["com.tencent.mqq"])
        pickerCount = 50
        try p.setHidden(false, id: p.entries[0].id)
        XCTAssertTrue(hidden.isEmpty)
    }
}
