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
    @State private var draft = FamilyActivitySelection()
    @State private var confirmRestore = false
    @State private var exportDocument: DiagnosticDocument?
    @State private var showingExporter = false
    @State private var preparingExport = false
    @State private var exportError = false

    var body: some View {
        NavigationStack {
            List {
                Section("1 · 个人授权") {
                    LabeledContent("系统状态", value: manager.authorizationText)
                    Button(manager.busy ? "正在请求…" : manager.requestOutstanding ? "系统请求尚未结束" : "请求 / 重试个人授权") {
                        manager.requestAuthorization()
                    }.disabled(manager.requestOutstanding || manager.approved)
                    Text(manager.authorizationStageText).font(.footnote)
                    if let issue = manager.authorizationIssue {
                        Text(issue).font(.footnote).foregroundStyle(.orange).textSelection(.enabled)
                    }
                    Button("导出诊断日志", action: exportDiagnostics).disabled(preparingExport)
                    Text("授权入口和使用历史仍由 iOS 保留。IPA 签名中存在 entitlement 不代表授权成功。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("2 · 先验证一个第三方 App") {
                    Button("选择 App") { draft = manager.selection; picking = true }
                        .disabled(!manager.approved || !manager.storageHealthy)
                    Text("在系统选择器中展开分类，勾选具体 App；不要只勾选分类。先选一个不影响日常使用的第三方 App，选“隐藏”，离开查看图标，再返回选“正常”验证恢复。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("3 · 逐 App 管理（已保存的请求状态）") {
                    if manager.entries.isEmpty { Text("尚未选择 App").foregroundStyle(.secondary) }
                    ForEach(manager.entries) { entry in
                        VStack(alignment: .leading, spacing: 12) {
                            Label(entry.token)
                            Picker("状态", selection: Binding(get: { entry.mode }, set: { manager.setMode($0, id: entry.id) })) {
                                ForEach(AppMode.allCases) { mode in Text(mode.title).tag(mode) }
                            }.pickerStyle(.segmented).disabled(!manager.storageHealthy)
                        }.padding(.vertical, 6)
                    }
                    Text("上锁会请求系统显示限制页。隐藏同时请求移除图标和限制启动。如果桌面或搜索仍显示图标，请点开检查限制页。选择正常可解除本工具的限制。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("恢复与退出") {
                    Button("恢复全部并退出", role: .destructive) { confirmRestore = true }
                    Text("进入后台只关闭管理入口，不改变限制。恢复的 App 不会被后台任务重新隐藏。若其他工具也限制同一 App，需要分别解除。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("诊断（可复制反馈）") {
                    Text(manager.diagnostic).font(.footnote.monospaced()).textSelection(.enabled)
                    Text("真机安装：待验证 · 个人授权：以系统状态为准 · 图标隐藏与限制页：待真机验收")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onAppear(perform: manager.resumeAuthorizationIfNeeded)
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
                NavigationStack {
                    FamilyActivityPicker(selection: $draft)
                        .navigationTitle("选择具体 App")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("取消") { picking = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("保存") { manager.select(draft); picking = false }
                            }
                        }
                }
            }
            .confirmationDialog("撤销本工具施加的全部限制并返回计算器？", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("恢复全部并退出", role: .destructive) { if manager.restoreAll() { exit() } }
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
