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
    @Published private(set) var requestOutstanding = false
    @Published private(set) var authorizationStageText = "尚未连接系统服务"
    @Published private(set) var storageHealthy = true
    @Published private(set) var policyReady = false
    @Published private(set) var policyBusy = false
    @Published private(set) var policyTimedOut = false
    private let policyWorker = AppPolicyWorker()
    private let authorizationProbe = AuthorizationProbe()
    private let approvalKey = "family-controls.previous-approval"
    private var checkedOnEntry = false
    private var authorizationObservation: AnyCancellable?

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
        guard policyReady, !checkedOnEntry else { return }
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
                self.requestOutstanding = true
                self.authorizationStageText = stage.rawValue
            case .timedOut(let stage):
                log.record("auth.\(attempt) deadline.exceeded limit_s=30 stage=\(stage)")
                self.authorizationStageText = "等待超时：\(stage.rawValue)"
                self.authorizationIssue = "等待 30 秒后系统仍未返回。可以退出管理页；系统返回后会更新状态。若一直卡住，请导出诊断日志。"
            case .failed(let error):
                log.record("auth.\(attempt) ui.error domain=\((error as NSError).domain) code=\((error as NSError).code)")
                self.requestOutstanding = false
                self.authorizationStageText = "系统返回错误"
                self.authorizationIssue = "个人授权失败\n" + self.describe(error)
            case .completed(let outcome):
                log.record("auth.\(attempt) ui.completed outcome=\(outcome)")
                self.requestOutstanding = false
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
    func loadPolicy() async {
        guard !policyReady else { return }
        await perform("load", message: "已读取本地管理记录。") { _ in }
    }

    func select(_ value: FamilyActivitySelection) async {
        guard approved else { diagnostic = "请先获得个人授权。"; return }
        let tokens = value.applicationTokens
        await perform("select", message: "已保存所选 App。") { try $0.select(tokens) }
    }

    func setMode(_ mode: AppMode, id: UUID) async {
        guard approved || mode == .normal else { diagnostic = "系统未授权，无法提交限制。"; return }
        await perform("mode.\(mode.rawValue)", message: "已向系统提交「\(mode.title)」请求。") {
            try $0.setMode(mode, id: id)
        }
    }

    func rename(_ nickname: String, id: UUID) async {
        await perform("rename", message: "已保存备注名称。") { try $0.rename(nickname, id: id) }
    }

    func restoreAll() async -> Bool {
        await perform("restore", message: "已请求解除本工具施加的全部限制。") { try $0.restoreAll() }
    }

    @discardableResult
    private func perform(_ operation: String, message: String,
                         work: @escaping @Sendable (PolicyController<ApplicationToken>) throws -> Void) async -> Bool {
        guard !policyBusy else { return false }
        let log = DiagnosticLog.shared
        policyBusy = true
        policyTimedOut = false
        log.record("policy.operation.begin kind=\(operation)")
        let deadline = Task {
            do { try await Task.sleep(nanoseconds: 5_000_000_000) }
            catch { return }
            policyTimedOut = true
            log.record("policy.operation.slow kind=\(operation)")
        }
        let update = await policyWorker.run(work)
        deadline.cancel()
        entries = update.entries
        storageHealthy = update.storageError == nil
        policyReady = true
        policyBusy = false
        policyTimedOut = false
        let error = update.operationError ?? update.storageError
        log.record("policy.operation.end kind=\(operation) count=\(update.entries.count) error=\(error != nil)")
        diagnostic = error.map(describe) ?? message
        return error == nil
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
