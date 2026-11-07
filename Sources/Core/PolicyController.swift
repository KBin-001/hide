import Foundation

enum AppMode: String, Codable, CaseIterable, Identifiable {
    case normal, locked, hidden
    var id: String { rawValue }
    var title: String {
        switch self { case .normal: return "正常"; case .locked: return "上锁"; case .hidden: return "隐藏" }
    }
}

struct AppEntry<Token: Codable & Hashable>: Codable, Identifiable {
    var id: UUID = UUID()
    let token: Token
    var mode: AppMode = .normal
    var nickname: String? = nil
}

struct PolicySnapshot<Token: Codable & Hashable>: Codable {
    var version = 1
    var entries: [AppEntry<Token>] = []
}

/// The single policy boundary: persist a complete next state, then submit only our restrictions.
/// Initialization and lifecycle events deliberately never reapply saved restrictions.
final class PolicyController<Token: Codable & Hashable> {
    private(set) var snapshot = PolicySnapshot<Token>()
    private(set) var loadError: Error?
    private let otherRestrictedCount: () -> Int
    private let save: (Data) throws -> Void
    private let apply: (Set<Token>, Set<Token>) -> Void

    init(load: () throws -> Data?, save: @escaping (Data) throws -> Void,
         otherRestrictedCount: @escaping () -> Int = { 0 },
         apply: @escaping (Set<Token>, Set<Token>) -> Void) {
        self.otherRestrictedCount = otherRestrictedCount
        self.save = save
        self.apply = apply
        do {
            if let data = try load() {
                let decoded = try JSONDecoder().decode(PolicySnapshot<Token>.self, from: data)
                guard decoded.version == 1,
                      Set(decoded.entries.map(\.token)).count == decoded.entries.count,
                      Set(decoded.entries.map(\.id)).count == decoded.entries.count else {
                    throw PolicyError.invalidState
                }
                snapshot = decoded
            }
        } catch { loadError = error }
    }

    func select(_ tokens: Set<Token>) throws {
        guard loadError == nil else { throw PolicyError.invalidState }
        var next = snapshot
        next.entries.removeAll { !tokens.contains($0.token) }
        let existing = Set(next.entries.map(\.token))
        next.entries += tokens.subtracting(existing).map { AppEntry(token: $0) }
        // A saved normal request can still have a stale system restriction after interruption.
        if snapshot.entries.contains(where: { !tokens.contains($0.token) }) {
            try commit(next)
        } else {
            try persist(next)
        }
    }

    func add(_ token: Token, nickname: String) throws {
        try add([(token: token, nickname: nickname)])
    }

    func add(_ additions: [(token: Token, nickname: String)]) throws {
        guard loadError == nil else { throw PolicyError.invalidState }
        var next = snapshot
        var known = Set(next.entries.map(\.token))
        for addition in additions where known.insert(addition.token).inserted {
            let name = addition.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            next.entries.append(AppEntry(token: addition.token, nickname: name.isEmpty ? nil : String(name.prefix(40))))
        }
        guard next.entries.count != snapshot.entries.count else { return }
        try persist(next)
    }

    func setMode(_ mode: AppMode, id: UUID) throws {
        guard loadError == nil else { throw PolicyError.invalidState }
        var next = snapshot
        guard let index = next.entries.firstIndex(where: { $0.id == id }) else { return }
        next.entries[index].mode = mode
        try commit(next)
    }

    func rename(_ nickname: String, id: UUID) throws {
        guard loadError == nil else { throw PolicyError.invalidState }
        var next = snapshot
        guard let index = next.entries.firstIndex(where: { $0.id == id }) else { return }
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        next.entries[index].nickname = name.isEmpty ? nil : String(name.prefix(40))
        try persist(next)
    }

    func restoreAll() throws {
        var next = snapshot
        for i in next.entries.indices { next.entries[i].mode = .normal }
        // Emergency release works even if the state file cannot be written.
        apply([], [])
        snapshot = next
        do { try save(JSONEncoder().encode(next)) }
        catch { loadError = error; throw error }
        loadError = nil
    }

    private func commit(_ next: PolicySnapshot<Token>) throws {
        let locked = Set(next.entries.filter { $0.mode == .locked }.map(\.token))
        let hidden = next.entries.filter { $0.mode == .hidden }.map(\.token)
        let restrictedCount = locked.count + hidden.count
        let limit = 50
        // Older versions allowed 50 per mode. Let those users reduce existing restrictions.
        guard restrictedCount + otherRestrictedCount() <= limit || restrictedCount < snapshot.entries.filter({ $0.mode != .normal }).count else {
            throw PolicyError.tooMany
        }
        let shielded = locked.union(hidden.prefix(max(0, limit - locked.count)))
        try persist(next)
        apply(shielded, Set(hidden))
    }

    private func persist(_ next: PolicySnapshot<Token>) throws {
        try save(JSONEncoder().encode(next))
        snapshot = next
    }
}

enum PolicyError: LocalizedError {
    case invalidState, tooMany
    var errorDescription: String? {
        switch self {
        case .invalidState: return "管理数据损坏或版本不兼容。请先恢复全部；不会自动重新施加限制。"
        case .tooMany: return "上锁与隐藏合计最多 50 个 App。请先将部分 App 改为正常。"
        }
    }
}
