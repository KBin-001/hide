import SwiftUI

struct AppCatalogPicker: View {
    @Environment(\.dismiss) private var dismiss
    let existingIDs: Set<String>
    let save: ([CatalogApp]) -> Void
    @State private var query = ""
    @State private var selected: Set<String> = []

    private var matching: [String: [CatalogApp]] {
        Dictionary(grouping: AppCatalog.apps.filter { $0.matches(query) }, by: \.category)
    }

    var body: some View {
        NavigationStack {
            catalogList
                .listStyle(.plain)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "搜索 App")
                .managementPage()
                .navigationTitle("选择 App")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
        }
        .safeAreaInset(edge: .bottom) { saveBar }
    }

    private var saveBar: some View {
        Button {
            save(AppCatalog.apps.filter { selected.contains($0.id) })
        } label: {
            Text("添加所选 App（\(selected.count)）")
        }
        .buttonStyle(ManagementPrimaryButton())
        .disabled(selected.isEmpty)
        .accessibilityIdentifier("catalog.save")
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(ManagementStyle.background)
        .overlay(alignment: .top) { Rectangle().fill(ManagementStyle.divider).frame(height: 1) }
    }

    private var catalogList: some View {
        let appsByCategory = matching
        return List {
            Section {
                Text("在内置的 \(AppCatalog.apps.count) 款常用 App 中搜索名称、别名或 Bundle ID。添加后默认正常。")
                    .font(.footnote)
                    .foregroundStyle(ManagementStyle.muted)
                    .managementRow()
            }
            if appsByCategory.isEmpty {
                Text("未找到，可返回管理页使用手动添加。")
                    .foregroundStyle(ManagementStyle.muted)
                    .managementRow()
            }
            ForEach(AppCatalog.categories, id: \.self) { category in
                if let apps = appsByCategory[category] { categorySection(category, apps: apps) }
            }
        }
    }

    private func categorySection(_ category: String, apps: [CatalogApp]) -> some View {
        Section {
            ForEach(apps) { app in
                CatalogSelectionRow(app: app, isExisting: existingIDs.contains(app.id),
                                    isSelected: selected.contains(app.id)) {
                    if !selected.insert(app.id).inserted { selected.remove(app.id) }
                }
                .managementRow()
            }
        } header: {
            Text(category).font(.subheadline.weight(.semibold)).foregroundStyle(ManagementStyle.muted)
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
            HStack(spacing: 12) {
                ManagementAppIcon(category: app.category)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).fontWeight(.medium).foregroundStyle(.primary)
                    Text(app.id).font(.caption).foregroundStyle(ManagementStyle.muted)
                }
                Spacer()
                if isExisting {
                    Text("已添加").font(.caption).foregroundStyle(ManagementStyle.muted)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? ManagementStyle.mint : ManagementStyle.muted)
                }
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isExisting)
        .accessibilityIdentifier("catalog.app." + app.id)
        .accessibilityLabel("\(app.name)，\(isExisting ? "已添加" : isSelected ? "已选中" : "未选中")")
    }
}
