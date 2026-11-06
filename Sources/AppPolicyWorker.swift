import Foundation
import ManagedSettings

/// Owns the policy file and the named store on one serial queue. ManagedSettings
/// calls can wait for another process, so the UI never accesses this store directly.
final class AppPolicyWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.personal.calculatorvault.policy", qos: .userInitiated)
    private lazy var store = ManagedSettingsStore(named: .init("calculator-vault-v1"))
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
                Thread.sleep(forTimeInterval: 30)
                return
            }
            #endif
            let ownStore = self.store
            log.record("policy.shield.begin")
            ownStore.shield.applications = shielded.isEmpty ? nil : shielded
            log.record("policy.shield.end")
            log.record("policy.blocked.begin")
            let blocked = Set(hidden.map { Application(token: $0) })
            ownStore.application.blockedApplications = blocked.isEmpty ? nil : blocked
            log.record("policy.blocked.end")
        })
    }()

    struct Update {
        let entries: [AppEntry<ApplicationToken>]
        let storageError: Error?
        let operationError: Error?
    }

    func run(_ operation: @escaping @Sendable (PolicyController<ApplicationToken>) throws -> Void) async -> Update {
        await withCheckedContinuation { continuation in
            queue.async {
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
                                                      operationError: error))
            }
        }
    }
}
