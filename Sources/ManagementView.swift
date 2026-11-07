import SwiftUI
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
    let changePIN: () -> Void
    let exit: () -> Void
    @State private var pickingCatalog = false
    @State private var showingRecovery = false
    @State private var addingBundleApp = false
    @State private var bundleName = ""
    @State private var bundleIdentifier = ""
    @State private var confirmRestore = false
    @State private var confirmResetList = false
    @State private var exportDocument: DiagnosticDocument?
    @State private var showingExporter = false
    @State private var preparingExport = false
    @State private var exportError = false
    @State private var recoveryAction: RecoveryAction?
    @State private var diagnosticsExpanded = false

    private enum RecoveryAction { case restoreAndExit, resetList }

    var body: some View {
        NavigationStack {
            catalogPresentedContent
        }
    }

    private var catalogPresentedContent: some View {
        editorContent
            .sheet(isPresented: $pickingCatalog) {
                AppCatalogPicker(existingIDs: Set(manager.bundleEntries.map(\.token))) { apps in
                    pickingCatalog = false
                    Task { await manager.addCatalogApps(apps) }
                }
            }
    }

    // Separate opaque return types keep the SwiftUI constraint solver's work bounded.
    private var editorContent: some View {
        presentedContent
            .alert("连接恢复说明", isPresented: $showingRecovery) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text("1. 长时间无响应时，先导出日志，再从 App 切换器关闭计算器。\n2. 到「设置 → 屏幕使用时间 → 有屏幕使用时间访问权限的 App」，只关闭计算器的权限。撤销会解除计算器施加的限制。\n3. 重开计算器，进入管理页后点一次「连接系统授权」。清空目录记录可用「诊断 → 清空管理列表」。")
            }
            .alert("清空管理列表？", isPresented: $confirmResetList) {
                Button("确认清空", role: .destructive) { recoveryAction = .resetList }
                Button("取消", role: .cancel) { }
            } message: {
                Text("先解除计算器施加的全部限制，再清除已选 App 和备注。你的 PIN 会保留。")
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
            .confirmationDialog("撤销本工具施加的全部限制并返回计算器？", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("确认恢复全部", role: .destructive) { recoveryAction = .restoreAndExit }
            }
    }

    private var navigationContent: some View {
        managementList
            .managementPage()
            .onAppear { DiagnosticLog.shared.record("management.entered") }
            .task { await manager.loadPolicy() }
            .task(id: recoveryAction) {
                guard let recoveryAction else { return }
                let restored = await manager.restoreAll(forgetApps: recoveryAction == .resetList)
                guard !Task.isCancelled else { return }
                self.recoveryAction = nil
                if restored, recoveryAction == .restoreAndExit { exit() }
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
        ScrollViewReader { scroll in
            List {
                authorizationSection
                bundleIDSection
                recoverySection
            }
            .listStyle(.plain)
            .onChange(of: diagnosticsExpanded) { expanded in
                if expanded {
                    withAnimation { scroll.scrollTo("management.export", anchor: .bottom) }
                }
            }
        }
    }

    private var authorizationSection: some View {
        Section {
            Group {
                LabeledContent {
                    Text(manager.authorizationText)
                        .font(.subheadline)
                        .foregroundStyle(manager.approved ? ManagementStyle.mint : ManagementStyle.muted)
                } label: {
                    Label {
                        Text("屏幕使用时间").fontWeight(.medium)
                    } icon: {
                        Image(systemName: manager.approved ? "checkmark.shield.fill" : "shield")
                            .foregroundStyle(manager.approved ? ManagementStyle.mint : ManagementStyle.muted)
                    }
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
                    Button("连接恢复说明") { showingRecovery = true }
                    Button("导出授权诊断日志", action: exportDiagnostics).disabled(preparingExport)
                }
            }
            .managementRow()
        }
    }

    private var recoverySection: some View {
        Section {
            recoveryActions
                .managementRow()
        } header: {
            sectionTitle("工具")
        }
    }

    private var recoveryActions: some View {
        Group {
            Button("恢复全部并退出", role: .destructive) { confirmRestore = true }
                .disabled(manager.policyBusy || !manager.policyReady)
                .accessibilityIdentifier("management.restore")
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
            Button(action: changePIN) { Label("更改 PIN", systemImage: "key") }
            diagnosticActions
        }
    }

    private var diagnosticActions: some View {
        Group {
            Button {
                diagnosticsExpanded.toggle()
            } label: {
                HStack {
                    Text("诊断")
                    Spacer()
                    Image(systemName: diagnosticsExpanded ? "chevron.down" : "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ManagementStyle.mint)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(diagnosticsExpanded ? "已展开" : "已折叠")
            if diagnosticsExpanded {
                Button("导出诊断日志", action: exportDiagnostics)
                    .disabled(preparingExport)
                    .id("management.export")
                Text(manager.diagnostic).font(.footnote).textSelection(.enabled)
                Button("手动添加（高级）") {
                    bundleName = ""
                    bundleIdentifier = ""
                    addingBundleApp = true
                }
                .disabled(!manager.policyReady || manager.policyBusy || !manager.storageHealthy)
                Button("清理旧选择器限制") { Task { await manager.restoreLegacy() } }
                    .disabled(manager.policyBusy || !manager.policyReady)
                Button("清空管理列表", role: .destructive) { confirmResetList = true }
                    .disabled(manager.policyBusy || !manager.policyReady)
            }
        }
    }

    private var bundleIDSection: some View {
        Section {
            Button {
                pickingCatalog = true
            } label: {
                Label("选择 App", systemImage: "plus.circle").fontWeight(.semibold)
            }
            .disabled(!manager.policyReady || manager.policyBusy || !manager.storageHealthy)
            .managementRow()
            ForEach(manager.bundleEntries) { entry in
                BundleIDAppRow(manager: manager, entry: entry)
                    .managementRow()
            }
        } header: {
            sectionTitle("目录 App · \(manager.bundleEntries.count)")
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ManagementStyle.muted)
            .textCase(nil)
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

private struct BundleIDAppRow: View {
    @ObservedObject var manager: AppManager
    let entry: AppEntry<String>

    var body: some View {
        HStack(spacing: 12) {
            ManagementAppIcon(category: AppCatalog.byID[entry.token]?.category)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.nickname ?? entry.token).fontWeight(.medium)
                if entry.nickname != nil {
                    Text(entry.token)
                        .font(.caption)
                        .foregroundStyle(ManagementStyle.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            actions
        }
        .disabled(manager.policyBusy)
    }

    private var actions: some View {
        Menu {
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
        } label: {
            ManagedStatusLabel(mode: entry.mode)
        }
        .accessibilityLabel("\(entry.nickname ?? entry.token)，已保存请求：\(entry.mode.title)")
    }
}

private struct ManagedStatusLabel: View {
    let mode: AppMode

    var body: some View {
        HStack(spacing: 6) {
            Label(mode.title, systemImage: statusIcon(for: mode))
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(mode == .normal ? ManagementStyle.muted : ManagementStyle.mint)
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background(ManagementStyle.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}

private func statusIcon(for mode: AppMode) -> String {
    switch mode {
    case .normal: return "checkmark.circle"
    case .locked: return "lock"
    case .hidden: return "eye.slash"
    }
}
