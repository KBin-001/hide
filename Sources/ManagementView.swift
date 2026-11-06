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
            List {
                Section {
                    Label {
                        LabeledContent("屏幕使用时间", value: manager.authorizationText)
                    } icon: {
                        Image(systemName: manager.approved ? "checkmark.shield.fill" : "shield")
                            .foregroundStyle(manager.approved ? Color.teal : Color.secondary)
                    }
                    if !manager.approved {
                        Button(manager.requestOutstanding ? manager.authorizationStageText : "连接系统授权") {
                            manager.requestAuthorization()
                        }.disabled(manager.requestOutstanding)
                    }
                    if let issue = manager.authorizationIssue {
                        Text(issue).font(.footnote).foregroundStyle(.orange).textSelection(.enabled)
                    }
                }
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
                    Button {
                        picking = true
                    } label: {
                        Label("选择 App", systemImage: "plus.circle")
                    }
                    .disabled(!manager.policyReady || manager.policyBusy || !manager.approved || !manager.storageHealthy)
                } header: {
                    Text("管理的 App · \(manager.entries.count)")
                } footer: {
                    Text("点状态可切换上锁、隐藏或正常。可设置备注名称，方便下次辨认。")
                }
                if manager.policyBusy {
                    Section {
                        if manager.policyTimedOut {
                            Label("系统处理较慢。仍可退出或导出日志。", systemImage: "clock")
                                .foregroundStyle(.orange)
                        } else {
                            ProgressView(manager.policyReady ? "正在提交…" : "正在读取记录…")
                        }
                    }
                }
                Section {
                    Button("恢复全部并退出", role: .destructive) { confirmRestore = true }
                        .disabled(manager.policyBusy || !manager.policyReady)
                        .accessibilityIdentifier("management.restore")
                    DisclosureGroup("诊断") {
                        Text(manager.diagnostic).font(.footnote).textSelection(.enabled)
                        Button("导出诊断日志", action: exportDiagnostics).disabled(preparingExport)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .tint(.teal)
            .onAppear { DiagnosticLog.shared.record("management.entered") }
            .task(id: manager.policyReady) {
                if manager.policyReady { manager.resumeAuthorizationIfNeeded() }
                else { await manager.loadPolicy() }
            }
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
