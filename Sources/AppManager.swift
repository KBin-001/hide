import SwiftUI
import FamilyControls
import ManagedSettings

@MainActor
final class AppManager: ObservableObject {
    @Published private(set) var entries: [AppEntry<ApplicationToken>] = []
    @Published private(set) var authorization: AuthorizationStatus = .notDetermined
    @Published var diagnostic = "尚未读取系统授权。点击个人授权按钮后才连接 Family Controls 服务。"
    @Published private(set) var busy = false
    @Published private(set) var requestOutstanding = false
    @Published private(set) var authorizationStageText = "尚未连接系统服务"
    @Published private(set) var storageHealthy = true
    private lazy var store = ManagedSettingsStore(named: .init("calculator-vault-v1"))
    private var policy: PolicyController<ApplicationToken>!
    private let authorizationProbe = AuthorizationProbe()

    init() {
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("management-v1.json")
        policy = PolicyController(load: {
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            return try Data(contentsOf: file)
        }, save: { data in
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }, apply: { [weak self] locked, hidden in
            guard let self = self else { return }
            let ownStore = self.store
            let blocked = Set(hidden.map { Application(token: $0) })
            // First remove obsolete restrictions, then add the new restrictions.
            // All assignments target our named store; no default/foreign stores are cleared.
            let remainingLocks = (ownStore.shield.applications ?? []).intersection(locked)
            let remainingHidden = (ownStore.application.blockedApplications ?? []).intersection(blocked)
            ownStore.shield.applications = remainingLocks.isEmpty ? nil : remainingLocks
            ownStore.application.blockedApplications = remainingHidden.isEmpty ? nil : remainingHidden
            ownStore.shield.applications = locked.isEmpty ? nil : locked
            ownStore.application.blockedApplications = blocked.isEmpty ? nil : blocked
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
    func requestAuthorization() {
        guard !authorizationProbe.isPending else { return }
        authorizationProbe.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .progress(let stage):
                self.busy = true; self.requestOutstanding = true
                self.authorizationStageText = stage.rawValue
                self.diagnostic = "授权进行中：\(stage.rawValue)。等待上限 30 秒。"
            case .timedOut(let stage):
                self.busy = false
                self.authorizationStageText = "等待超时：\(stage.rawValue)"
                self.diagnostic = "30 秒内系统未返回。阶段：\(stage.rawValue)。\n尚未获得授权，选择 App 仍不可用。系统没有返回 NSError，因此目前无法确定是系统服务还是安装签名身份导致。\n底层请求可能仍在运行，不会重复发起；迟到的结果会更新界面。可以退出管理页。请复制这段诊断反馈。"
            case .failed(let error):
                self.busy = false; self.requestOutstanding = false
                self.authorizationStageText = "系统返回错误"
                self.diagnostic = "个人授权失败\n" + self.describe(error)
            case .completed(let outcome):
                self.busy = false; self.requestOutstanding = false
                switch outcome {
                case .approved: self.authorization = .approved
                case .denied: self.authorization = .denied
                case .notDetermined: self.authorization = .notDetermined
                }
                self.authorizationStageText = "系统已返回"
                self.diagnostic = "授权请求返回；系统状态：\(self.authorizationText)。请选一个第三方 App 验证隐藏与恢复。"
            }
        }
        authorizationProbe.start { report in
            report(.initializing)
            let center = AuthorizationCenter.shared
            report(.requesting)
            try await center.requestAuthorization(for: .individual)
            report(.readingStatus)
            switch center.authorizationStatus {
            case .approved: return .approved
            case .denied: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
        }
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
