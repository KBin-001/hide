import SwiftUI

struct AppCatalogPicker: View {
    @Environment(\.dismiss) private var dismiss
    let existingIDs: Set<String>
    let save: ([CatalogApp]) -> Void
    @State private var query = ""
    @State private var selected: Set<String> = []

    private var matching: [CatalogApp] {
        AppCatalog.apps.filter { $0.matches(query) }
    }

    var body: some View {
        NavigationStack {
            catalogList
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "名称、别名或 Bundle ID")
                .navigationTitle("选择 App")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("添加（\(selected.count)）") {
                            save(AppCatalog.apps.filter { selected.contains($0.id) })
                        }
                        .disabled(selected.isEmpty)
                        .accessibilityIdentifier("catalog.save")
                    }
                }
        }
    }

    private var catalogList: some View {
        List {
            Section {
                Text("内置 \(AppCatalog.apps.count) 款常用应用，按名称选择即可。列表不是手机已安装清单；添加后默认正常，隐藏需要系统授权。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if matching.isEmpty {
                Text("未找到，可返回管理页使用手动添加。")
            }
            ForEach(AppCatalog.categories, id: \.self) { category in
                categorySection(category)
            }
        }
    }

    @ViewBuilder
    private func categorySection(_ category: String) -> some View {
        let apps = matching.filter { $0.category == category }
        if !apps.isEmpty {
            Section(category) {
                ForEach(apps) { app in
                    CatalogSelectionRow(app: app, isExisting: existingIDs.contains(app.id),
                                        isSelected: selected.contains(app.id)) {
                        if !selected.insert(app.id).inserted { selected.remove(app.id) }
                    }
                }
            }
        }
    }
}

private struct CatalogSelectionRow: View {
    let app: CatalogApp
    let isExisting: Bool
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).foregroundStyle(.primary)
                    Text(app.id).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isExisting {
                    Text("已添加").font(.caption).foregroundStyle(.secondary)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(isExisting)
        .accessibilityIdentifier("catalog.app." + app.id)
        .accessibilityLabel("\(app.name)，\(isExisting ? "已添加" : isSelected ? "已选中" : "未选中")")
    }
}
