import SwiftUI

@main
struct CalculatorApp: App {
    var body: some Scene { WindowGroup { RootView().preferredColorScheme(.dark) } }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var manager = AppManager()
    @State private var calculator = CalculatorEngine()
    @State private var needsPIN = false
    @State private var keychainReady = false
    @State private var managing = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !keychainReady {
                VStack(spacing: 20) {
                    Text("计算器").font(.largeTitle)
                    Text("正在读取安全设置")
                    Button("重试") { checkPIN() }
                }
            } else if needsPIN {
                PINSetupView {
                    needsPIN = false
                    calculator.clear()
                }
            } else if managing {
                ManagementView(manager: manager) {
                    managing = false
                    calculator.clear()
                }
            } else {
                CalculatorView(engine: calculator, press: press)
            }
            if scenePhase != .active {
                Color.black.ignoresSafeArea()
                Image(systemName: "plus.forwardslash.minus").font(.system(size: 64)).foregroundStyle(.gray)
            }
        }
        .task { checkPIN() }
        .onChange(of: scenePhase) { phase in
            if phase == .background { managing = false; calculator.clear() }
            if phase == .active { manager.refreshAuthorization() }
        }
        .alert("安全存储", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func checkPIN() {
        do { needsPIN = try !PINStore.exists(); keychainReady = true }
        catch { self.error = error.localizedDescription; keychainReady = false }
    }
    private func press(_ key: String) {
        if key == "=", let candidate = calculator.pinCandidate, (4...12).contains(candidate.count) {
            do {
                if try PINStore.matches(candidate) {
                    calculator.clear(); managing = true; return
                }
            } catch { self.error = error.localizedDescription }
        }
        calculator.press(key)
    }
}

struct PINSetupView: View {
    let done: () -> Void
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var message = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("首次设置") {
                    Text("设置 4–12 位数字 PIN。以后先按 AC，输入 PIN，再按 = 打开管理页。请妥善记住 PIN。")
                    SecureField("PIN", text: $pin).keyboardType(.numberPad).textContentType(.newPassword)
                    SecureField("再次输入", text: $confirmation).keyboardType(.numberPad)
                    Button("保存到 Keychain") {
                        guard pin == confirmation else { message = "两次 PIN 不一致。"; return }
                        do { try PINStore.create(pin); pin = ""; confirmation = ""; done() }
                        catch { message = error.localizedDescription }
                    }
                    if !message.isEmpty { Text(message).foregroundStyle(.orange) }
                }
                Section {
                    Text("管理功能使用 iOS 屏幕使用时间个人授权。忘记 PIN 时，可从系统设置撤销本工具的屏幕使用时间访问以解除限制；卸载不保证清除 Keychain。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置计算器")
        }
    }
}

struct CalculatorView: View {
    let engine: CalculatorEngine
    let press: (String) -> Void
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
                            Button { press(key) } label: {
                                Text(key).font(.system(size: 30, weight: .medium, design: .rounded))
                                    .frame(width: key == "0" ? unit * 2 + gap : unit, height: height)
                                    .foregroundStyle(["AC", "+/−", "%"].contains(key) ? .black : .white)
                                    .background(color(key), in: Capsule())
                            }.buttonStyle(.plain)
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
