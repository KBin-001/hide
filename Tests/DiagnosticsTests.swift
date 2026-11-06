import XCTest
@testable import CalculatorCore

final class DiagnosticsTests: XCTestCase {
    func testExportRetainsRecentEventsAcrossSessions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = DiagnosticLog(directory: directory, limit: 2)
        first.record("obsolete-event")
        first.record("center.shared.begin")
        first.record("deadline.exceeded")
        _ = await first.snapshot()

        let reopened = DiagnosticLog(directory: directory, limit: 2)
        let report = String(decoding: await reopened.snapshot(), as: UTF8.self)
        XCTAssertTrue(report.contains("center.shared.begin"))
        XCTAssertTrue(report.contains("deadline.exceeded"))
        XCTAssertFalse(report.contains("obsolete-event"))
    }

    func testReadsOnlyAllowlistedInstalledEntitlementFields() throws {
        func words(_ values: [UInt32], bigEndian: Bool) -> Data {
            Data(values.flatMap { value in
                withUnsafeBytes(of: bigEndian ? value.bigEndian : value.littleEndian) { Array($0) }
            })
        }
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "com.apple.developer.family-controls": true,
            "application-identifier": "TROLLTROLL.com.personal.calculatorvault",
            "keychain-access-groups": ["do-not-export-group-value"]
        ], format: .xml, options: 0)
        let signatureSize = UInt32(28 + plist.count)
        var binary = words([0xfeedfacf, 0, 0, 0, 1, 16, 0, 0, 0x1d, 16, 48, signatureSize], bigEndian: false)
        binary.append(words([0xfade0cc0, signatureSize, 1, 5, 20, 0xfade7171, UInt32(8 + plist.count)], bigEndian: true))
        binary.append(plist)
        let summary = InstalledSignature.summary(of: binary)
        XCTAssertTrue(summary.contains("family_controls=true"))
        XCTAssertTrue(summary.contains("keychain_group_count=1"))
        XCTAssertFalse(summary.contains("do-not-export-group-value"))
        XCTAssertEqual(InstalledSignature.summary(of: Data(binary.dropLast())), "signature_blob=invalid")
    }
}
