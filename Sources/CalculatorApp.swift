import LocalAuthentication
import SwiftUI

@main
struct CalculatorApp: App {
    var body: some Scene { WindowGroup { RootView().preferredColorScheme(.dark) } }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var calculator = CalculatorEngine()
    @State private var needsPIN = false
    @State private var keychainReady = false
    @State private var keychainLoading = false
    @State private var managing = false
    @State private var manager: AppManager?
    @State private var error: String?
    @State private var pinEditor: PINEditor.Mode?
    @State private var recoveryContext: LAContext?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !keychainReady {
                VStack(spacing: 20) {
                    Text("计算器").font(.largeTitle)
                    ProgressView()
                    Text("正在读取 Keychain 安全设置")
                    Button("重试") { Task { await checkPIN() } }.disabled(keychainLoading)
                }
            } else if needsPIN {
                PINEditor(mode: .setup) {
                    needsPIN = false
                    calculator.clear()
                }
            } else if managing, let manager {
                ManagementView(manager: manager, changePIN: { pinEditor = .change }) {
                    managing = false
                    calculator.clear()
                }
            } else {
                CalculatorView(engine: calculator, press: press, resetPIN: authenticatePINReset)
            }
            if scenePhase == .background || (scenePhase == .inactive && keychainReady) {
                Color.black.ignoresSafeArea()
                Image(systemName: "plus.forwardslash.minus").font(.system(size: 64)).foregroundStyle(.gray)
            }
        }
        .task {
            recordAppConfiguration()
            await checkPIN()
        }
        .onChange(of: scenePhase) { phase in
            DiagnosticLog.shared.record("scene.phase=\(phase)")
            if phase == .background {
                managing = false
                calculator.clear()
                pinEditor = nil
                recoveryContext?.invalidate()
                recoveryContext = nil
            }
        }
        .sheet(item: $pinEditor) { mode in
            PINEditor(mode: mode) {
                calculator.clear()
                pinEditor = nil
            }
        }
        .alert("安全存储", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }
    @MainActor private func recordAppConfiguration() {
        let bundle = Bundle.main
        let info = bundle.infoDictionary ?? [:]
        let provisioning = bundle.url(forResource: "embedded", withExtension: "mobileprovision") != nil
        DiagnosticLog.shared.record("app.root_ready version=\(info["CFBundleShortVersionString"] ?? "unknown") build=\(info["CFBundleVersion"] ?? "unknown") bundle=\(bundle.bundleIdentifier ?? "unknown") os=\(ProcessInfo.processInfo.operatingSystemVersionString) sdk=\(info["DTSDKName"] ?? "unknown") min_os=\(info["MinimumOSVersion"] ?? "unknown") provisioning_file=\(provisioning)")
        Task.detached(priority: .utility) {
            DiagnosticLog.shared.record("app.installed_signature \(InstalledSignature.current.summary)")
        }
    }
    @MainActor private func checkPIN() async {
        guard !keychainLoading else { return }
        keychainLoading = true
        defer { keychainLoading = false }
        do {
            let exists = try await Task.detached(priority: .userInitiated) { try PINStore.exists() }.value
            needsPIN = !exists; keychainReady = true
        }
        catch { self.error = error.localizedDescription; keychainReady = false }
    }
    @MainActor private func press(_ key: String) {
        if key == "=", let candidate = calculator.pinCandidate, (4...12).contains(candidate.count) {
            do {
                if try PINStore.matches(candidate) {
                    if manager == nil { manager = AppManager() }
                    calculator.clear(); managing = true; return
                }
            } catch { self.error = error.localizedDescription }
        }
        calculator.press(key)
    }

    @MainActor private func authenticatePINReset() {
        guard recoveryContext == nil, pinEditor == nil, scenePhase == .active else { return }
        let context = LAContext()
        recoveryContext = context
        Task {
            do {
                let verified = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                    localizedReason: "验证设备所有者身份以重置计算器的 PIN。")
                guard recoveryContext === context else { return }
                recoveryContext = nil
                if verified { pinEditor = .reset }
            } catch {
                guard recoveryContext === context else { return }
                recoveryContext = nil
                let code = (error as? LAError)?.code
                guard code != .userCancel, code != .systemCancel, code != .appCancel else { return }
                self.error = code == .passcodeNotSet
                    ? "请先在 iOS 设置中设置锁屏密码，再重置计算器 PIN。"
                    : "设备身份验证失败。\(error.localizedDescription)"
            }
        }
    }
}

private struct PINEditor: View {
    enum Mode: String, Identifiable {
        case setup, change, reset
        var id: Self { self }
        var title: String {
            switch self {
            case .setup: return "设置计算器"
            case .change: return "更改 PIN"
            case .reset: return "重置 PIN"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    let done: () -> Void
    @State private var currentPIN = ""
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if mode == .change {
                        SecureField("当前 PIN", text: $currentPIN).keyboardType(.numberPad)
                    }
                    SecureField("新 PIN", text: $pin).keyboardType(.numberPad)
                    SecureField("再次输入", text: $confirmation).keyboardType(.numberPad)
                    Button("保存到 Keychain", action: save)
                    if let message { Text(message).foregroundStyle(.orange) }
                } footer: {
                    Text("设置 4–12 位数字。按 AC、输入 PIN，再按 = 打开管理页。忘记 PIN 时，可长按 AC 并验证设备身份来重置。")
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                if mode != .setup {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                }
            }
        }
    }

    private func save() {
        guard pin == confirmation else { message = "两次 PIN 不一致。"; return }
        do {
            if mode == .change, try !PINStore.matches(currentPIN) {
                message = "当前 PIN 不正确。"
                return
            }
            if mode == .setup { try PINStore.create(pin) }
            else { try PINStore.replace(pin) }
            done()
        } catch {
            message = error.localizedDescription
        }
    }
}

struct CalculatorView: View {
    let engine: CalculatorEngine
    let press: (String) -> Void
    let resetPIN: () -> Void
    private let rows = [["AC", "+/−", "%", "÷"], ["7", "8", "9", "×"],
                        ["4", "5", "6", "−"], ["1", "2", "3", "+"], ["0", ".", "="]]
    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 12
            let unit = (geometry.size.width - 48 - gap * 3) / 4
            let height = min(unit, max(48, (geometry.size.height - 150) / 5 - gap))
            VStack(spacing: gap) {
                Spacer(minLength: 10)
                Text(engine.display)
                    .font(.system(size: 72, weight: .light, design: .rounded))
                    .minimumScaleFactor(0.28).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.bottom, 18).accessibilityLabel("结果 \(engine.display)")
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(row, id: \.self) { key in
                            let button = Button { press(key) } label: {
                                Text(key).font(.system(size: 30, weight: .medium, design: .rounded))
                                    .frame(width: key == "0" ? unit * 2 + gap : unit, height: height)
                                    .foregroundStyle(["AC", "+/−", "%"].contains(key) ? .black : .white)
                                    .background(color(key), in: Capsule())
                            }.buttonStyle(.plain)
                            if key == "AC" {
                                button.contextMenu {
                                    Button(action: resetPIN) {
                                        Label("重置 PIN（验证设备身份）", systemImage: "key")
                                    }
                                }
                            } else {
                                button
                            }
                        }
                    }
                }
            }.padding(24).frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
    private func color(_ key: String) -> Color {
        if ["÷", "×", "−", "+", "="].contains(key) { return .orange }
        return ["AC", "+/−", "%"].contains(key) ? Color(white: 0.68) : Color(white: 0.18)
    }
}
