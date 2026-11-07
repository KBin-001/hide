import Foundation
import ManagedSettings

/// Keeps the policy file and this app's ManagedSettings stores on one serial queue.
final class AppPolicyWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.personal.calculatorvault.policy", qos: .userInitiated)
    private lazy var defaultStore = ManagedSettingsStore()
    private lazy var legacyStore = ManagedSettingsStore(named: .init("calculator-vault-v1"))
    private lazy var bundleIDStore = ManagedSettingsStore(named: .init("calculator-qq-id-probe"))
    private var restrictionWriteVerified: Bool?
    #if DEBUG && targetEnvironment(simulator)
    private var simulatedStall = false
    #endif
    // Keep reading this file for upgrades and restrict its system writes to recovery.
    private lazy var legacyPolicy: PolicyController<ApplicationToken> = {
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("management-v1.json")
        return PolicyController(load: {
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            return try Data(contentsOf: file)
        }, save: { data in
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }, apply: { [unowned self] _, _ in
            let log = DiagnosticLog.shared
            log.record("policy.legacy.restore.begin")
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
            let shieldMatches = self.submit([], at: \.shield.applications, name: "shield")
            let blockedMatches = self.submit([], at: \.application.blockedApplications, name: "blocked")
            self.recordVerification(shieldMatches && blockedMatches)
            log.record("policy.legacy.restore.end shield_verified=\(shieldMatches) blocked_verified=\(blockedMatches)")
        })
    }()

    private func submit<Value: Hashable>(
        _ desired: Set<Value>, at keyPath: ReferenceWritableKeyPath<ManagedSettingsStore, Set<Value>?>, name: String
    ) -> Bool {
        RestrictionStoreRouting.submit(desired) { location, values in
            write(values, at: keyPath, name: name, location: location.rawValue,
                  store: location == .defaultStore ? defaultStore : legacyStore)
        }
    }

    private func write<Value: Hashable>(
        _ values: Set<Value>, at keyPath: ReferenceWritableKeyPath<ManagedSettingsStore, Set<Value>?>,
        name: String, location: String, store: @autoclosure () -> ManagedSettingsStore
    ) -> Bool {
        let log = DiagnosticLog.shared
        log.record("policy.write.begin kind=\(name) store=\(location) requested=\(values.count)")
        let target = store()
        target[keyPath: keyPath] = values.isEmpty ? nil : values
        var stored = target[keyPath: keyPath] ?? []
        if stored != values {
            Thread.sleep(forTimeInterval: 0.3)
            stored = target[keyPath: keyPath] ?? []
        }
        let matches = stored == values
        log.record("policy.write.end kind=\(name) store=\(location) readback=\(stored.count) matches=\(matches)")
        return matches
    }

    // Retain the store name used by the successful QQ test, including its recovery path.
    private lazy var bundlePolicy: BundleIDPolicy = {
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bundle-id-management-v1.json")
        return BundleIDPolicy(ownBundleID: Bundle.main.bundleIdentifier ?? "com.personal.calculatorvault", load: {
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            return try Data(contentsOf: file)
        }, save: { data in
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }, otherRestrictedCount: { [unowned self] in
            self.legacyPolicy.snapshot.entries.filter { $0.mode != .normal }.count
        }, apply: { [unowned self] identifiers in
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["CALCULATOR_TEST_SLOW_MANAGED_SETTINGS"] == "1" { return }
            #endif
            let apps = Set(identifiers.map { Application(bundleIdentifier: $0) })
            self.recordVerification(self.write(apps, at: \.application.blockedApplications,
                                              name: "blocked.bundle_id", location: "bundleID", store: self.bundleIDStore))
        })
    }()

    private func recordVerification(_ matches: Bool) {
        restrictionWriteVerified = (restrictionWriteVerified ?? true) && matches
    }

    func load() async -> Update {
        await run { }
    }

    func editBundleApps(_ operation: @escaping @Sendable (BundleIDPolicy) throws -> Void) async -> Update {
        await run { [self] in try operation(bundlePolicy) }
    }

    func restoreLegacy() async -> Update {
        await run { [self] in try clearLegacyRestrictions() }
    }

    private func clearLegacyRestrictions() throws {
        try legacyPolicy.restoreAll()
        if restrictionWriteVerified != false, !legacyPolicy.snapshot.entries.isEmpty {
            try legacyPolicy.forgetRestoredApps()
        }
    }

    func restoreAll(forgetApps: Bool = false) async -> Update {
        await run { [self] in
            var firstError: Error?
            do { try clearLegacyRestrictions() } catch { firstError = error }
            // Always attempt both stores, even if one state file cannot be saved.
            do { try bundlePolicy.restoreAll() } catch { if firstError == nil { firstError = error } }
            if let firstError { throw firstError }
            // Retain selections when the system still reports any of our restrictions.
            if forgetApps, restrictionWriteVerified != false {
                try bundlePolicy.forgetRestoredApps()
            }
        }
    }

    struct Update {
        let bundleEntries: [AppEntry<String>]
        let storageError: Error?
        let operationError: Error?
        let restrictionWriteVerified: Bool?
    }

    private func run(_ operation: @escaping @Sendable () throws -> Void) async -> Update {
        await withCheckedContinuation { continuation in
            queue.async {
                self.restrictionWriteVerified = nil
                let error: Error?
                do {
                    try operation()
                    error = nil
                } catch let failure {
                    error = failure
                }
                continuation.resume(returning: Update(bundleEntries: self.bundlePolicy.entries,
                                                      storageError: self.bundlePolicy.loadError,
                                                      operationError: error,
                                                      restrictionWriteVerified: self.restrictionWriteVerified))
            }
        }
    }
}
