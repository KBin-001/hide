import SwiftUI
import Combine
import FamilyControls
import ManagedSettings

@MainActor
final class AppManager: ObservableObject {
    @Published private(set) var entries: [AppEntry<ApplicationToken>] = []
    @Published private(set) var authorization: AuthorizationStatus = .notDetermined
    @Published private(set) var diagnostic = "在此查看 App 限制提交结果。"
    @Published private(set) var authorizationIssue: String?
    @Published private(set) var busy = false
    @Published private(set) var requestOutstanding = false
    @Published private(set) var authorizationStageText = "尚未连接系统服务"
    @Published private(set) var storageHealthy = true
    private lazy var store = ManagedSettingsStore(named: .init("calculator-vault-v1"))
    private var policy: PolicyController<ApplicationToken>!
    private let authorizationProbe = AuthorizationProbe()
    private let approvalKey = "family-controls.previous-approval"
    private var checkedOnEntry = false
    private var authorizationObservation: AnyCancellable?

    init() {
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("management-v1.json")
        policy = PolicyController(load: {
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            return try Data(contentsOf: file)
        }, save: { data in
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }, apply: { [weak self] shielded, hidden in
            guard let self = self else { return }
            let blocked = Set(hidden.map { Application(token: $0) })
            // Set the shield first so a transition out of hidden can keep the launch restriction.
            DiagnosticLog.shared.record("policy.submit.begin shield=\(shielded.count) blocked=\(blocked.count)")
            let ownStore = self.store
            ownStore.shield.applications = shielded.isEmpty ? nil : shielded
            ownStore.application.blockedApplications = blocked.isEmpty ? nil : blocked
            let storedShield = ownStore.shield.applications ?? []
            let storedBlocked = ownStore.application.blockedApplications ?? []
            DiagnosticLog.shared.record("policy.submit.end shield=\(storedShield.count) blocked=\(storedBlocked.count) shield_matches=\(storedShield == shielded) blocked_matches=\(storedBlocked == blocked)")
        })
        entries = policy.snapshot.entries
        if let error = policy.loadError { storageHealthy = false; diagnostic = describe(error) }
    }

    var selection: FamilyActivitySelection {
        var value = FamilyActivitySelection()
        value.applicationTokens = Set(entries.map(\.token))
        return value
    }
    var approved: Bool { authorization == .approved }
    var authorizationText: String {
        switch authorization {
        case .approved: return "已授权"
        case .denied: return "已拒绝"
        case .notDetermined: return "未读取 / 尚未决定"
        @unknown default: return "未知状态"
        }
    }
    func resumeAuthorizationIfNeeded() {
        DiagnosticLog.shared.record("management.entered")
        guard !checkedOnEntry else { return }
        checkedOnEntry = true
        // A saved selection from older builds also indicates prior approval.
        let previousApproval = UserDefaults.standard.object(forKey: approvalKey) as? Bool ?? !entries.isEmpty
        if previousApproval { requestAuthorization(refreshing: true) }
    }

    func requestAuthorization(refreshing: Bool = false) {
        guard !authorizationProbe.isPending else { return }
        let attempt = String(UUID().uuidString.prefix(8))
        let log = DiagnosticLog.shared
        let trigger = refreshing ? "management_entry" : "manual"
        authorizationIssue = nil
        log.record("auth.\(attempt) started trigger=\(trigger) app_state=\(UIApplication.shared.applicationState.rawValue) protected_data_available=\(UIApplication.shared.isProtectedDataAvailable)")
        authorizationProbe.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .progress(let stage):
                self.busy = true; self.requestOutstanding = true
                self.authorizationStageText = stage.rawValue
            case .timedOut(let stage):
                log.record("auth.\(attempt) deadline.exceeded limit_s=30 stage=\(stage)")
                self.busy = false
                self.authorizationStageText = "等待超时：\(stage.rawValue)"
                self.authorizationIssue = "等待 30 秒后系统仍未返回。可以退出管理页；系统返回后会更新状态。若一直卡住，请导出诊断日志。"
            case .failed(let error):
                log.record("auth.\(attempt) ui.error domain=\((error as NSError).domain) code=\((error as NSError).code)")
                self.busy = false; self.requestOutstanding = false
                self.authorizationStageText = "系统返回错误"
                self.authorizationIssue = "个人授权失败\n" + self.describe(error)
            case .completed(let outcome):
                log.record("auth.\(attempt) ui.completed outcome=\(outcome)")
                self.busy = false; self.requestOutstanding = false
                self.authorizationStageText = "系统已返回"
                self.authorizationIssue = nil
            }
        }
        authorizationProbe.start { [weak self] report in
            log.record("auth.\(attempt) worker.started")
            report(.initializing)
            log.record("auth.\(attempt) center.shared.begin")
            let center = AuthorizationCenter.shared
            log.record("auth.\(attempt) center.shared.end")
            report(.requesting)
            log.record("auth.\(attempt) request.individual.begin")
            do {
                try await center.requestAuthorization(for: .individual)
                log.record("auth.\(attempt) request.individual.end")
            } catch {
                var underlying: NSError? = error as NSError
                for depth in 0..<4 {
                    guard let current = underlying else { break }
                    log.record("auth.\(attempt) request.error depth=\(depth) domain=\(current.domain) code=\(current.code)")
                    underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError
                }
                throw error
            }
            report(.readingStatus)
            log.record("auth.\(attempt) status.read.begin")
            let status = await MainActor.run { [weak self] in
                let status = center.authorizationStatus
                self?.updateAuthorization(status)
                self?.observeAuthorization(center)
                return status
            }
            log.record("auth.\(attempt) status.read.end status=\(status)")
            switch status {
            case .approved: return .approved
            case .denied: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
        }
    }

    private func observeAuthorization(_ center: AuthorizationCenter) {
        guard authorizationObservation == nil else { return }
        authorizationObservation = center.$authorizationStatus.dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.updateAuthorization(status) }
    }

    private func updateAuthorization(_ status: AuthorizationStatus) {
        authorization = status
        UserDefaults.standard.set(approved, forKey: approvalKey)
        DiagnosticLog.shared.record("auth.status.updated status=\(status)")
    }
    func select(_ value: FamilyActivitySelection) {
        guard approved else { diagnostic = "请先获得个人授权。"; return }
        perform {
            try policy.select(value.applicationTokens)
            diagnostic = "选择已保存。只管理单个 App；分类和网站选择不会生效。移除的 App 已撤销本工具限制。"
        }
    }
    func setMode(_ mode: AppMode, id: UUID) {
        guard approved || mode == .normal else { diagnostic = "系统未授权，无法提交限制。"; return }
        perform {
            try policy.setMode(mode, id: id)
            diagnostic = "已保存并向系统提交“\(mode.title)”请求。实际图标/限制页效果须在真机确认。"
        }
    }
    @discardableResult func restoreAll() -> Bool {
        do {
            try policy.restoreAll()
            entries = policy.snapshot.entries; storageHealthy = true
            diagnostic = "已清空本工具的上锁和隐藏请求；不会在后台或重开时重新施加。其他工具的限制可能仍然存在。"
            return true
        } catch {
            entries = policy.snapshot.entries; storageHealthy = false
            diagnostic = "已请求撤销限制，但保存失败；请保持在管理页重试恢复全部。\n" + describe(error)
            return false
        }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action(); entries = policy.snapshot.entries }
        catch { diagnostic = describe(error) }
    }
    private func describe(_ error: Error) -> String {
        let e = error as NSError
        var text = "\(e.localizedDescription)\nDomain: \(e.domain)\nCode: \(e.code)"
        if let reason = e.localizedFailureReason { text += "\nReason: \(reason)" }
        if let suggestion = e.localizedRecoverySuggestion { text += "\nRecovery: \(suggestion)" }
        if let underlying = e.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += "\nUnderlying: \(underlying.domain) / \(underlying.code): \(underlying.localizedDescription)"
        }
        return text + "\niOS \(UIDevice.current.systemVersion) · \(Bundle.main.bundleIdentifier ?? "unknown")"
    }
}
