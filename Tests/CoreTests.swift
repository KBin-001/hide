import XCTest
@testable import CalculatorCore

final class CoreTests: XCTestCase {
    func testHideRestoreAndIsolationSurviveReload() throws {
        var saved: Data?
        var locks = Set<String>(), hidden = Set<String>()
        var writes = 0
        func controller() -> PolicyController<String> {
            PolicyController(load: { saved }, save: { saved = $0 }, apply: {
                locks = $0; hidden = $1; writes += 1
            })
        }
        let p = controller()
        try p.select(["A", "B"])
        let a = try XCTUnwrap(p.snapshot.entries.first { $0.token == "A" }?.id)
        let b = try XCTUnwrap(p.snapshot.entries.first { $0.token == "B" }?.id)
        try p.setMode(.hidden, id: a)
        XCTAssertEqual(hidden, ["A"])
        try p.setMode(.locked, id: b)
        try p.setMode(.normal, id: a)
        XCTAssertEqual(hidden, []); XCTAssertEqual(locks, ["B"])
        let before = writes
        let reloaded = controller()
        XCTAssertEqual(writes, before, "Opening the app must never reapply restrictions")
        XCTAssertEqual(reloaded.snapshot.entries.first { $0.id == a }?.mode, .normal)
        try reloaded.restoreAll()
        XCTAssertTrue(locks.isEmpty && hidden.isEmpty)
    }

    func testRemovalReleasesAndFailureDoesNotApply() throws {
        var hidden = Set<String>()
        var fail = false
        let p = PolicyController<String>(load: { nil }, save: { _ in
            if fail { throw CocoaError(.fileWriteNoPermission) }
        }, apply: { _, value in hidden = value })
        try p.select(["A", "B"])
        let a = try XCTUnwrap(p.snapshot.entries.first { $0.token == "A" }?.id)
        try p.setMode(.hidden, id: a)
        fail = true
        XCTAssertThrowsError(try p.setMode(.normal, id: a))
        XCTAssertEqual(hidden, ["A"])
        // Emergency release still submits even if persistence fails.
        XCTAssertThrowsError(try p.restoreAll())
        XCTAssertEqual(hidden, [])
        fail = false
        try p.restoreAll()
        try p.select(["B"])
        XCTAssertEqual(hidden, [])
    }

    func testCorruptStateNeverAppliesAndCanRecover() throws {
        var calls = 0
        let p = PolicyController<String>(load: { Data("broken".utf8) }, save: { _ in }, apply: { _, _ in calls += 1 })
        XCTAssertNotNil(p.loadError); XCTAssertEqual(calls, 0)
        XCTAssertThrowsError(try p.select(["A"]))
        try p.restoreAll()
        try p.select(["A"])
        XCTAssertEqual(p.snapshot.entries.count, 1)
    }

    func testLimitAndModeTransition() throws {
        let p = PolicyController<String>(load: { nil }, save: { _ in }, apply: { locked, hidden in
            XCTAssertTrue(locked.isDisjoint(with: hidden))
        })
        try p.select(Set((0..<51).map(String.init)))
        for entry in p.snapshot.entries.prefix(50) { try p.setMode(.hidden, id: entry.id) }
        let last = p.snapshot.entries[50]
        XCTAssertThrowsError(try p.setMode(.hidden, id: last.id))
        try p.setMode(.locked, id: p.snapshot.entries[0].id)
        try p.setMode(.hidden, id: last.id)
    }

    func testCalculatorAndPINEntry() {
        var c = CalculatorEngine()
        ["0", "0", "1", "2"].forEach { c.press($0) }
        XCTAssertEqual(c.pinCandidate, "0012")
        c.press("+"); XCTAssertNil(c.pinCandidate)
        c.press("3"); c.press("="); XCTAssertEqual(c.display, "15")
        c.press("="); XCTAssertEqual(c.display, "18")
        c.clear(); ["8", "÷", "0", "="].forEach { c.press($0) }
        XCTAssertEqual(c.display, "错误")
        c.press("7"); XCTAssertEqual(c.display, "7")
        for (op, expected) in [("+", "10"), ("−", "6"), ("×", "16"), ("÷", "4")] {
            c.clear(); ["8", op, "2", "="].forEach { c.press($0) }
            XCTAssertEqual(c.display, expected)
        }
        c.clear(); ["0", ".", "1", "+", "0", ".", "2", "="].forEach { c.press($0) }
        XCTAssertEqual(c.display, "0.3")
    }
}
