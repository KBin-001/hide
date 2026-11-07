import Foundation

enum AuthorizationStage: String, Sendable {
    case checkingSignature = "检查安装签名"
    case initializing = "初始化系统授权中心"
    case requesting = "等待系统授权与身份认证"
    case readingStatus = "读取系统授权结果"
}

enum AuthorizationOutcome: Sendable { case approved, denied, notDetermined }

/// A deadline must not join a task group: the underlying OS IPC may never finish,
/// and cancelling its Swift task does not cancel the system request.
@MainActor
final class AuthorizationProbe {
    enum Event {
        case progress(AuthorizationStage)
        case completed(AuthorizationOutcome)
        case failed(Error)
        case timedOut(AuthorizationStage)
    }
    typealias Work = @Sendable (@escaping @Sendable (AuthorizationStage) -> Void) async throws -> AuthorizationOutcome
    var onEvent: ((Event) -> Void)?
    private(set) var isPending = false
    private var stage = AuthorizationStage.checkingSignature
    private var timeoutNanoseconds: UInt64 = 30_000_000_000
    private var deadline: Task<Void, Never>?

    @discardableResult
    func start(timeoutNanoseconds: UInt64 = 30_000_000_000, work: @escaping Work) -> Bool {
        guard !isPending else { return false }
        isPending = true; stage = .checkingSignature
        onEvent?(.progress(stage))
        self.timeoutNanoseconds = timeoutNanoseconds
        armDeadline()
        Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<AuthorizationOutcome, Error>
            do {
                result = .success(try await work { [weak probe = self] stage in
                    Task { @MainActor [weak probe] in probe?.report(stage) }
                })
            } catch { result = .failure(error) }
            await self?.finish(result)
        }
        return true
    }
    private func report(_ stage: AuthorizationStage) {
        guard isPending else { return }
        guard self.stage != stage else { return }
        self.stage = stage
        armDeadline()
        onEvent?(.progress(stage))
    }
    private func armDeadline() {
        deadline?.cancel()
        deadline = Task { [weak self] in
            guard let timeout = self?.timeoutNanoseconds else { return }
            do { try await Task.sleep(nanoseconds: timeout) }
            catch { return }
            guard let self, self.isPending else { return }
            self.onEvent?(.timedOut(self.stage))
        }
    }
    private func finish(_ result: Result<AuthorizationOutcome, Error>) {
        deadline?.cancel(); deadline = nil; isPending = false
        switch result {
        case .success(let value): onEvent?(.completed(value))
        case .failure(let error): onEvent?(.failed(error))
        }
    }
    deinit { deadline?.cancel() }
}
