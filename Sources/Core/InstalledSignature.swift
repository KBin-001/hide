import Foundation

/// Reads the XML entitlement slot of our installed, thin 64-bit Mach-O executable.
/// This is file metadata only. Slot numbers follow Apple's XNU cs_blobs.h.
enum InstalledSignature {
    enum FamilyControls: String, Sendable { case present, missing, unknown }

    struct Report: Sendable {
        let summary: String
        let familyControls: FamilyControls

        init(_ summary: String, familyControls: FamilyControls = .unknown) {
            self.summary = summary
            self.familyControls = familyControls
        }
    }

    static let current: Report = {
        guard let executable = Bundle.main.executableURL,
              let data = try? Data(contentsOf: executable, options: .mappedIfSafe) else {
            return Report("executable=unreadable")
        }
        return inspect(data)
    }()

    static func inspect(_ data: Data) -> Report {
        func word(_ offset: Int, bigEndian: Bool = false) -> Int? {
            guard offset >= 0, offset <= data.count - 4 else { return nil }
            let bytes = (0..<4).map { Int(data[offset + $0]) }
            let ordered = bigEndian ? bytes : Array(bytes.reversed())
            return ordered.reduce(0) { ($0 << 8) | $1 }
        }

        guard word(0) == 0xfeedfacf, let count = word(16), let commandBytes = word(20),
              commandBytes <= data.count - 32, count <= commandBytes / 8 else {
            return Report("mach_o=unsupported")
        }
        var cursor = 32
        let commandEnd = cursor + commandBytes
        for _ in 0..<count {
            guard cursor <= commandEnd - 8, let type = word(cursor), let commandSize = word(cursor + 4),
                  commandSize >= 8, commandSize <= commandEnd - cursor else { return Report("load_commands=invalid") }
            defer { cursor += commandSize }
            // LC_CODE_SIGNATURE contains the file offset and length of the embedded superblob.
            guard type == 0x1d else { continue }
            guard commandSize >= 16, let start = word(cursor + 8), let signatureSize = word(cursor + 12),
                  signatureSize >= 12, start <= data.count - signatureSize,
                  word(start, bigEndian: true) == 0xfade0cc0,
                  let length = word(start + 4, bigEndian: true), length >= 12, length <= signatureSize,
                  let slots = word(start + 8, bigEndian: true), slots <= (length - 12) / 8 else {
                return Report("signature_blob=invalid")
            }
            var derPresent = false
            var entitlements: [String: Any]?
            for index in 0..<slots {
                let slot = start + 12 + index * 8
                if word(slot, bigEndian: true) == 7 { derPresent = true }
                guard word(slot, bigEndian: true) == 5, let offset = word(slot + 4, bigEndian: true),
                      offset >= 12 + slots * 8, offset <= length - 8,
                      word(start + offset, bigEndian: true) == 0xfade7171,
                      let size = word(start + offset + 4, bigEndian: true),
                      size >= 8, size <= length - offset else { continue }
                let payload = data.subdata(in: (start + offset + 8)..<(start + offset + size))
                entitlements = (try? PropertyListSerialization.propertyList(from: payload, format: nil)) as? [String: Any]
            }
            guard let entitlements else { return Report("xml_entitlements=unavailable der_slot=\(derPresent)") }
            let familyControls = entitlements["com.apple.developer.family-controls"] as? Bool
            let appID = entitlements["application-identifier"] as? String ?? "missing"
            let teamID = entitlements["com.apple.developer.team-identifier"] as? String ?? "missing"
            let groupCount = (entitlements["keychain-access-groups"] as? [String])?.count ?? 0
            return Report("xml_entitlements=read der_slot=\(derPresent) family_controls=\(familyControls.map { String($0) } ?? "missing") app_id=\(appID) team_id=\(teamID) keychain_group_count=\(groupCount)",
                          familyControls: familyControls == true ? .present : .missing)
        }
        return Report("signature_command=missing")
    }
}
