import Foundation

/// Uses independently supplied identifiers, never attempts to decode picker tokens.
final class BundleIDPolicy {
    private let policy: PolicyController<String>
    private let ownBundleID: String
    var entries: [AppEntry<String>] { policy.snapshot.entries }
    var loadError: Error? { policy.loadError }

    init(ownBundleID: String, load: () throws -> Data?, save: @escaping (Data) throws -> Void,
         otherRestrictedCount: @escaping () -> Int = { 0 }, apply: @escaping (Set<String>) -> Void) {
        self.ownBundleID = ownBundleID
        policy = PolicyController(load: load, save: save, otherRestrictedCount: otherRestrictedCount,
                                  apply: { _, hidden in apply(hidden) })
    }

    func add(identifier: String, name: String) throws {
        let value = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        guard value.utf8.count <= 255, parts.count >= 2,
              parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }),
              value.caseInsensitiveCompare(ownBundleID) != .orderedSame else {
            throw IdentifierError.invalid
        }
        try policy.add(value, nickname: name)
    }

    func setHidden(_ hidden: Bool, id: UUID) throws {
        try policy.setMode(hidden ? .hidden : .normal, id: id)
    }

    func remove(id: UUID) throws {
        try policy.select(Set(entries.filter { $0.id != id }.map(\.token)))
    }

    func restoreAll() throws { try policy.restoreAll() }

    enum IdentifierError: LocalizedError {
        case invalid
        var errorDescription: String? { "请输入有效的 Bundle ID（例如 com.tencent.mqq），不能添加本工具自身。" }
    }
}
