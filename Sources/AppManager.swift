import SwiftUI
import Combine
import FamilyControls
import ManagedSettings

@MainActor
final class AppManager: ObservableObject {
    @Published private(set) var bundleEntries: [AppEntry<String>] = []
    @Published private(set) var entries: [AppEntry<ApplicationToken>] = []
    @Published private(set) var authorization: AuthorizationStatus = .notDetermined
    @Published private(set) var diagnostic = "在此查看 App 限制提交结果。"
    @Published private(set) var authorizationIssue: String?
    @Published private(set) var requestOutstanding = false
    @Published private(set) var authorizationTimedOut = false
    @Published private(set) var authorizationSignatureMissing = false
    @Published private(set) var authorizationStageText = "尚未连接系统服务"
    @Published private(set) var storageHealthy = true
    @Published private(set) var policyReady = false
    @Published private(set) var policyBusy = false
    @Published private(set) var policyTimedOut = false
    @Published private(set) var policyIssue: String?
    private let policyWorker = AppPolicyWorker()
    private let authorizationProbe = AuthorizationProbe()
    private let approvalKey = "family-controls.previous-approval"
    private var authorizationObservation: AnyCancellable?

    var selection: FamilyActivitySelection {
        var value = FamilyActivitySelection()
        value.applicationTokens = Set(entries.map(\.token))
        return value
    }
    var approved: Bool { authorization == .approved }
    var authorizationText: String {
        if authorizationSignatureMissing { return "签名缺少权限" }
        switch authorization {
        case .approved: return "已授权"
        case .denied: return "已拒绝"
        case .notDetermined: return previouslyApproved ? "此前已授权，待确认" : "未连接"
        @unknown default: return "未知状态"
        }
    }
    private var previouslyApproved: Bool {
        let defaults = UserDefaults.standard
        // Older builds may only have a saved selection as evidence of a previous grant.
        if defaults.object(forKey: approvalKey) == nil { return !entries.isEmpty }
        return defaults.bool(forKey: approvalKey)
    }

    func requestAuthorization() {
        guard !authorizationProbe.isPending, !authorizationSignatureMissing else { return }
        guard UIApplication.shared.applicationState == .active else {
            authorizationIssue = "请在计算器回到前台后再连接系统授权。"
            return
        }
        let attempt = String(UUID().uuidString.prefix(8))
        let log = DiagnosticLog.shared
        authorizationIssue = nil
        authorizationTimedOut = false
        log.record("auth.\(attempt) started trigger=manual previous_approval=\(previouslyApproved) protected_data_available=\(UIApplication.shared.isProtectedDataAvailable)")
        authorizationProbe.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .progress(let stage):
                self.authorizationTimedOut = false
                self.authorizationIssue = nil
                self.requestOutstanding = true
                self.authorizationStageText = stage.rawValue
            case .timedOut(let stage):
                log.record("auth.\(attempt) stage.deadline.exceeded limit_s=30 stage=\(stage)")
                self.authorizationTimedOut = true
                self.authorizationIssue = "\(stage.rawValue)已等待 30 秒，系统仍在处理。可以继续等待；服务返回后会自动更新。若一直无响应，请查看连接恢复说明。"
            case .failed(let error):
                log.record("auth.\(attempt) ui.error domain=\((error as NSError).domain) code=\((error as NSError).code)")
                self.authorizationTimedOut = false
                self.requestOutstanding = false
                if error is AuthorizationSigningError {
                    self.authorizationSignatureMissing = true
                    self.authorizationIssue = "当前安装的签名缺少 Family Controls 权限。需要使用已为此 App ID 开启 Family Controls 的 Apple 开发签名。"
                } else {
                    self.authorizationIssue = "个人授权失败\n" + self.describe(error)
                }
            case .completed(let outcome):
                log.record("auth.\(attempt) ui.completed outcome=\(outcome)")
                self.authorizationTimedOut = false
                self.requestOutstanding = false
                self.authorizationIssue = nil
            }
        }
        authorizationProbe.start { [weak self] report in
            log.record("auth.\(attempt) worker.started")
            let signingState = InstalledSignature.current.familyControls
            log.record("auth.\(attempt) signing.check family_controls=\(signingState.rawValue)")
            guard signingState != .missing else { throw AuthorizationSigningError.missingFamilyControls }
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
        await perform("load", message: "已读取本地管理记录。") { await policyWorker.run { _ in } }
    }

    func select(_ value: FamilyActivitySelection) async {
        guard approved else { diagnostic = "请先获得个人授权。"; return }
        let tokens = value.applicationTokens
        await perform("select", message: "已保存所选 App。") {
            await policyWorker.run { try $0.select(tokens) }
        }
    }

    func setMode(_ mode: AppMode, id: UUID) async {
        guard approved || mode == .normal else { diagnostic = "系统未授权，无法提交限制。"; return }
        await perform("mode.\(mode.rawValue)", message: "已向系统提交「\(mode.title)」请求。") {
            await policyWorker.run { try $0.setMode(mode, id: id) }
        }
    }

    func rename(_ nickname: String, id: UUID) async {
        await perform("rename", message: "已保存备注名称。") {
            await policyWorker.run { try $0.rename(nickname, id: id) }
        }
    }

    func addBundleApp(identifier: String, name: String) async {
        guard storageHealthy else { return }
        await perform("bundle.add", message: "已添加，尚未施加限制。") {
            await policyWorker.editBundleApps { try $0.add(identifier: identifier, name: name) }
        }
    }

    func addCatalogApps(_ apps: [CatalogApp]) async {
        guard storageHealthy else { return }
        let additions = apps.map { (identifier: $0.id, name: $0.name) }
        await perform("bundle.catalog.add", message: "已保存所选 App，默认正常，尚未施加限制。") {
            await policyWorker.editBundleApps { try $0.addApps(additions) }
        }
    }

    func setBundleHidden(_ hidden: Bool, id: UUID) async {
        guard approved || !hidden else { return }
        await perform(hidden ? "bundle.hide" : "bundle.restore",
                      message: hidden ? "已提交隐藏请求，请到桌面确认效果。" : "已提交恢复请求，请到桌面确认效果。") {
            await policyWorker.editBundleApps { try $0.setHidden(hidden, id: id) }
        }
    }

    func removeBundleApp(id: UUID) async {
        await perform("bundle.remove", message: "已移除，并提交剩余 App 的隐藏设置。") {
            await policyWorker.editBundleApps { try $0.remove(id: id) }
        }
    }

    func restoreAll() async -> Bool {
        await perform("restore", message: "已请求解除本工具施加的全部限制。") { await policyWorker.restoreAll() }
    }

    @discardableResult
    private func perform(_ operation: String, message: String,
                         work: () async -> AppPolicyWorker.Update) async -> Bool {
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
        let update = await work()
        deadline.cancel()
        entries = update.entries
        bundleEntries = update.bundleEntries
        storageHealthy = update.storageError == nil
        policyReady = true
        policyBusy = false
        policyTimedOut = false
        let error = update.operationError ?? update.storageError
        let verification = update.restrictionWriteVerified.map { $0 ? "matched" : "mismatch" } ?? "not_checked"
        log.record("policy.operation.end kind=\(operation) count=\(update.entries.count) error=\(error != nil) verification=\(verification)")
        if let verified = update.restrictionWriteVerified {
            policyIssue = verified ? nil : "iOS 读回的限制与请求不一致。请导出诊断日志。"
            if !verified {
                diagnostic = error.map(describe) ?? "已记录请求。至少一项系统设置读回不匹配，请查看诊断日志中的写入结果。"
                return false
            }
        }
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

private enum AuthorizationSigningError: Error {
    case missingFamilyControls
}
