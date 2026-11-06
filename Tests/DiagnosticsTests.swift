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
        let binary = try executable(entitlements: [
            "com.apple.developer.family-controls": true,
            "application-identifier": "TROLLTROLL.com.personal.calculatorvault",
            "keychain-access-groups": ["do-not-export-group-value"]
        ])
        let report = InstalledSignature.inspect(binary)
        XCTAssertEqual(report.familyControls, .present)
        XCTAssertTrue(report.summary.contains("family_controls=true"))
        XCTAssertTrue(report.summary.contains("keychain_group_count=1"))
        XCTAssertFalse(report.summary.contains("do-not-export-group-value"))
        let truncated = InstalledSignature.inspect(Data(binary.dropLast()))
        XCTAssertEqual(truncated.summary, "signature_blob=invalid")
        XCTAssertEqual(truncated.familyControls, .unknown)
    }

    func testDistinguishesMissingFamilyControlsFromUnavailableXML() throws {
        let reSigned = try executable(entitlements: ["application-identifier": "TEST.com.personal.calculatorvault"])
        XCTAssertEqual(InstalledSignature.inspect(reSigned).familyControls, .missing)
        let derOnly = try executable(entitlements: nil)
        XCTAssertEqual(InstalledSignature.inspect(derOnly).familyControls, .unknown)
    }

    private func executable(entitlements: [String: Any]?) throws -> Data {
        func words(_ values: [UInt32], bigEndian: Bool) -> Data {
            Data(values.flatMap { value in
                withUnsafeBytes(of: bigEndian ? value.bigEndian : value.littleEndian) { Array($0) }
            })
        }
        let plist = try entitlements.map { try PropertyListSerialization.data(fromPropertyList: $0, format: .xml, options: 0) } ?? Data()
        let signatureSize = UInt32(28 + plist.count)
        var binary = words([0xfeedfacf, 0, 0, 0, 1, 16, 0, 0, 0x1d, 16, 48, signatureSize], bigEndian: false)
        let slot: UInt32 = entitlements == nil ? 7 : 5
        binary.append(words([0xfade0cc0, signatureSize, 1, slot, 20, 0xfade7171, UInt32(8 + plist.count)], bigEndian: true))
        binary.append(plist)
        return binary
    }
}
