import Foundation
import ManagedSettings

/// Keeps the policy file and this app's ManagedSettings stores on one serial queue.
final class AppPolicyWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.personal.calculatorvault.policy", qos: .userInitiated)
    private lazy var defaultStore = ManagedSettingsStore()
    private lazy var legacyStore = ManagedSettingsStore(named: .init("calculator-vault-v1"))
    private var restrictionWriteVerified: Bool?
    #if DEBUG && targetEnvironment(simulator)
    private var simulatedStall = false
    #endif
    private lazy var policy: PolicyController<ApplicationToken> = {
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("management-v1.json")
        return PolicyController(load: {
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            return try Data(contentsOf: file)
        }, save: { data in
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }, apply: { [unowned self] shielded, hidden in
            let log = DiagnosticLog.shared
            log.record("policy.store.begin shield=\(shielded.count) blocked=\(hidden.count)")
            #if DEBUG && targetEnvironment(simulator)
            // The UI regression exercises a slow system boundary without connecting to Screen Time.
            if ProcessInfo.processInfo.environment["CALCULATOR_TEST_SLOW_MANAGED_SETTINGS"] == "1" {
                if !self.simulatedStall {
                    self.simulatedStall = true
                    Thread.sleep(forTimeInterval: 25)
                }
                return
            }
            #endif
            let shieldMatches = self.submit(shielded, at: \.shield.applications, name: "shield")
            let blocked = Set(hidden.map { Application(token: $0) })
            let blockedMatches = self.submit(blocked, at: \.application.blockedApplications, name: "blocked")
            self.restrictionWriteVerified = shieldMatches && blockedMatches
            log.record("policy.store.end shield_verified=\(shieldMatches) blocked_verified=\(blockedMatches)")
        })
    }()

    private func submit<Value: Hashable>(
        _ desired: Set<Value>, at keyPath: ReferenceWritableKeyPath<ManagedSettingsStore, Set<Value>?>, name: String
    ) -> Bool {
        RestrictionStoreRouting.submit(desired) { location, values in
            let log = DiagnosticLog.shared
            log.record("policy.write.begin kind=\(name) store=\(location.rawValue) requested=\(values.count)")
            let store = location == .defaultStore ? defaultStore : legacyStore
            store[keyPath: keyPath] = values.isEmpty ? nil : values
            var stored = store[keyPath: keyPath] ?? []
            if stored != values {
                Thread.sleep(forTimeInterval: 0.3)
                stored = store[keyPath: keyPath] ?? []
            }
            let matches = stored == values
            log.record("policy.write.end kind=\(name) store=\(location.rawValue) readback=\(stored.count) matches=\(matches)")
            return matches
        }
    }

    struct Update {
        let entries: [AppEntry<ApplicationToken>]
        let storageError: Error?
        let operationError: Error?
        let restrictionWriteVerified: Bool?
    }

    func run(_ operation: @escaping @Sendable (PolicyController<ApplicationToken>) throws -> Void) async -> Update {
        await withCheckedContinuation { continuation in
            queue.async {
                self.restrictionWriteVerified = nil
                let policy = self.policy
                let error: Error?
                do {
                    try operation(policy)
                    error = nil
                } catch let failure {
                    error = failure
                }
                continuation.resume(returning: Update(entries: policy.snapshot.entries,
                                                      storageError: policy.loadError,
                                                      operationError: error,
                                                      restrictionWriteVerified: self.restrictionWriteVerified))
            }
        }
    }
}
