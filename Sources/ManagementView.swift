import SwiftUI
import FamilyControls
import ManagedSettings
import UniformTypeIdentifiers

private struct DiagnosticDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct ManagementView: View {
    @ObservedObject var manager: AppManager
    let exit: () -> Void
    @State private var picking = false
    @State private var showingRecovery = false
    @State private var addingBundleApp = false
    @State private var bundleName = ""
    @State private var bundleIdentifier = ""
    @State private var confirmRestore = false
    @State private var exportDocument: DiagnosticDocument?
    @State private var showingExporter = false
    @State private var preparingExport = false
    @State private var exportError = false
    @State private var restoreRequested = false
    @State private var editingID: UUID?
    @State private var nickname = ""
    @State private var renaming = false

    var body: some View {
        NavigationStack {
            editorContent
        }
    }

    // Separate opaque return types keep the SwiftUI constraint solver's work bounded.
    private var editorContent: some View {
        presentedContent
            .alert("连接恢复说明", isPresented: $showingRecovery) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text("1. 若进度继续变化，请等待系统弹窗或返回结果。\n2. 长时间无响应时，先导出日志，再从 App 切换器关闭计算器并重新连接。\n3. 若仍卡在初始化，重启手机后再试；本次真机测试通过此方式恢复。\n\niOS 未提供强制重置授权服务的公开接口。未完成的请求不能安全取消，因此不会叠加重试或自动撤销已有权限。恢复 App 可使用“恢复全部并退出”。")
            }
            .alert("添加 App", isPresented: $addingBundleApp) {
                TextField("名称（可选）", text: $bundleName)
                TextField("Bundle ID，例如 com.tencent.mqq", text: $bundleIdentifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("添加") {
                    let identifier = bundleIdentifier
                    let name = bundleName
                    Task { await manager.addBundleApp(identifier: identifier, name: name) }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("填写从可信来源核实的 App 标识。添加后默认为正常，不会立即隐藏。")
            }
            .alert("备注名称", isPresented: $renaming) {
                TextField("例如：社交 App", text: $nickname)
                Button("保存") {
                    guard let id = editingID else { return }
                    let name = nickname
                    Task { await manager.rename(name, id: id) }
                }
                Button("取消", role: .cancel) { }
            }
    }

    private var presentedContent: some View {
        navigationContent
            .fileExporter(isPresented: $showingExporter, document: exportDocument,
                          contentType: .plainText, defaultFilename: "Calculator-Authorization-Diagnostics") { result in
                if case .failure = result { exportError = true }
            }
            .alert("日志导出失败", isPresented: $exportError) {
                Button("好", role: .cancel) { }
            } message: {
                Text("请重新导出并选择一个可写入的文件夹。")
            }
            .sheet(isPresented: $picking) {
                AppSelectionSheet(selection: manager.selection) { selection in
                    picking = false
                    Task { await manager.select(selection) }
                }
            }
            .confirmationDialog("撤销本工具施加的全部限制并返回计算器？", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("确认恢复全部", role: .destructive) { restoreRequested = true }
            }
    }

    private var navigationContent: some View {
        managementList
            .listStyle(.insetGrouped)
            .tint(.teal)
            .onAppear { DiagnosticLog.shared.record("management.entered") }
            .task { await manager.loadPolicy() }
            .task(id: restoreRequested) {
                guard restoreRequested else { return }
                let restored = await manager.restoreAll()
                guard !Task.isCancelled else { return }
                restoreRequested = false
                if restored { exit() }
            }
            .navigationTitle("App 管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("退出") {
                        DiagnosticLog.shared.record("management.exit_tapped")
                        exit()
                    }
                }
            }
    }

    private var managementList: some View {
        List {
            authorizationSection
            recoverySection
            bundleIDSection
            pickerSection
        }
    }

    private var authorizationSection: some View {
        Section {
            Label {
                LabeledContent("屏幕使用时间", value: manager.authorizationText)
            } icon: {
                Image(systemName: manager.approved ? "checkmark.shield.fill" : "shield")
                    .foregroundStyle(manager.approved ? Color.teal : Color.secondary)
            }
            if manager.requestOutstanding {
                if !manager.authorizationTimedOut {
                    ProgressView(manager.authorizationStageText)
                }
            } else if !manager.approved && !manager.authorizationSignatureMissing {
                Button("连接系统授权", action: manager.requestAuthorization)
            }
            if let issue = manager.authorizationIssue {
                Text(issue).font(.footnote).foregroundStyle(.orange).textSelection(.enabled)
            }
            if manager.authorizationTimedOut {
                Button("连接恢复说明") { showingRecovery = true }
                Button("导出授权诊断日志", action: exportDiagnostics).disabled(preparingExport)
            }
            Button {
                picking = true
            } label: {
                Label("选择 App", systemImage: "plus.circle")
            }
            .disabled(!manager.policyReady || manager.policyBusy || !manager.approved || !manager.storageHealthy)
        }
    }

    private var recoverySection: some View {
        Section {
            Button("恢复全部并退出", role: .destructive) { confirmRestore = true }
                .disabled(manager.policyBusy || !manager.policyReady)
                .accessibilityIdentifier("management.restore")
            DisclosureGroup("诊断") {
                Text(manager.diagnostic).font(.footnote).textSelection(.enabled)
                Button("导出诊断日志", action: exportDiagnostics).disabled(preparingExport)
            }
            if let issue = manager.policyIssue, !manager.policyBusy {
                Text(issue).font(.footnote).foregroundStyle(.orange)
            }
            if manager.policyBusy {
                if manager.policyTimedOut {
                    Label("系统处理较慢。仍可退出或导出日志。", systemImage: "clock")
                        .foregroundStyle(.orange)
                } else {
                    ProgressView(manager.policyReady ? "正在提交…" : "正在读取记录…")
                }
            }
        }
    }

    private var bundleIDSection: some View {
        Section {
            Button("添加 QQ") {
                Task { await manager.addBundleApp(identifier: "com.tencent.mqq", name: "QQ") }
            }
            .disabled(!manager.policyReady || manager.policyBusy || !manager.storageHealthy ||
                      qqAlreadyAdded)
            Button("添加其他 App") {
                bundleName = ""
                bundleIdentifier = ""
                addingBundleApp = true
            }
            .disabled(!manager.policyReady || manager.policyBusy || !manager.storageHealthy)
            ForEach(manager.bundleEntries) { entry in
                BundleIDAppRow(manager: manager, entry: entry)
            }
        } header: {
            Text("按 App 标识隐藏")
        } footer: {
            Text("QQ 已在 iOS 16.3 真机验证。其他 App 需填写准确的 Bundle ID，并逐项确认隐藏与恢复效果。不会自动读取已安装 App；此入口仅提供隐藏和恢复。若同一 App 也在下方选择器中设有限制，需要两处都恢复正常。\n" + manager.diagnostic)
        }
    }

    private var pickerSection: some View {
        Section {
            ForEach(Array(manager.entries.enumerated()), id: \.element.id) { index, entry in
                ManagedAppRow(title: entry.nickname ?? "App \(index + 1)", mode: entry.mode,
                              canRestrict: manager.approved) { mode in
                    Task { await manager.setMode(mode, id: entry.id) }
                } edit: {
                    editingID = entry.id
                    nickname = entry.nickname ?? ""
                    renaming = true
                }
                .disabled(manager.policyBusy || !manager.storageHealthy)
            }
        } header: {
            Text("管理的 App · \(manager.entries.count)")
        } footer: {
            Text("点状态可切换上锁、隐藏或正常。可设置备注名称，方便下次辨认。")
        }
    }

    private var qqAlreadyAdded: Bool {
        manager.bundleEntries.contains { $0.token == "com.tencent.mqq" }
    }

    private func exportDiagnostics() {
        preparingExport = true
        Task {
            DiagnosticLog.shared.record("diagnostics.export_requested")
            exportDocument = DiagnosticDocument(data: await DiagnosticLog.shared.snapshot())
            preparingExport = false
            showingExporter = true
        }
    }
}

private struct AppSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FamilyActivitySelection
    let save: (FamilyActivitySelection) -> Void

    init(selection: FamilyActivitySelection, save: @escaping (FamilyActivitySelection) -> Void) {
        _draft = State(initialValue: selection)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            FamilyActivityPicker(selection: $draft)
                .navigationTitle("选择具体 App")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save(draft) } }
                }
        }
    }
}

private struct ManagedAppRow: View {
    let title: String
    let mode: AppMode
    let canRestrict: Bool
    let change: (AppMode) -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.fill")
                .font(.title2)
                .foregroundStyle(.teal)
                .accessibilityHidden(true)
            Text(title).font(.body.weight(.medium))
            Spacer(minLength: 8)
            Menu {
                ForEach(AppMode.allCases) { option in
                    Button {
                        change(option)
                    } label: {
                        Label(option.title, systemImage: option == mode ? "checkmark" : icon(for: option))
                    }
                    .disabled(option != .normal && !canRestrict)
                }
                Button(action: edit) { Label("备注名称", systemImage: "pencil") }
            } label: {
                Label(mode.title, systemImage: icon(for: mode))
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(Color.teal.opacity(0.12), in: Capsule())
            }
            .accessibilityLabel("\(title)，已保存请求：\(mode.title)")
        }
    }

    private func icon(for mode: AppMode) -> String {
        switch mode {
        case .normal: return "checkmark.circle"
        case .locked: return "lock"
        case .hidden: return "eye.slash"
        }
    }
}

private struct BundleIDAppRow: View {
    @ObservedObject var manager: AppManager
    let entry: AppEntry<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.nickname ?? entry.token)
                Spacer()
                actions
            }
            Text(entry.token).font(.caption).foregroundStyle(.secondary)
        }
        .disabled(manager.policyBusy)
    }

    private var actions: some View {
        Menu(entry.mode == .hidden ? "隐藏请求已保存" : "正常请求已保存") {
            Button("隐藏") {
                Task { await manager.setBundleHidden(true, id: entry.id) }
            }
            .disabled(!manager.approved || !manager.storageHealthy)
            Button("恢复正常") {
                Task { await manager.setBundleHidden(false, id: entry.id) }
            }
            .disabled(!manager.storageHealthy)
            Button("恢复并移除", role: .destructive) {
                Task { await manager.removeBundleApp(id: entry.id) }
            }
            .disabled(!manager.storageHealthy)
        }
    }
}
