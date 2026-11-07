import SwiftUI

enum ManagementStyle {
    static let background = Color(red: 0.08, green: 0.095, blue: 0.115)
    static let surface = Color(red: 0.125, green: 0.15, blue: 0.18)
    static let divider = Color.white.opacity(0.14)
    static let muted = Color(red: 0.66, green: 0.70, blue: 0.74)
    static let mint = Color(red: 0.545, green: 0.895, blue: 0.749)
}

extension View {
    func managementPage() -> some View {
        scrollContentBackground(.hidden)
            .background(ManagementStyle.background.ignoresSafeArea())
            .toolbarBackground(ManagementStyle.background, for: .navigationBar)
            .tint(ManagementStyle.mint)
    }

    func managementRow() -> some View {
        listRowBackground(ManagementStyle.background)
            .listRowSeparatorTint(ManagementStyle.divider)
    }
}

struct ManagementPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(isEnabled ? ManagementStyle.background : ManagementStyle.muted)
            .background(isEnabled ? ManagementStyle.mint : ManagementStyle.surface,
                        in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct ManagementAppIcon: View {
    var category: String? = nil

    private static let symbols = [
        "社交社区": "bubble.left.and.bubble.right", "视频直播": "play.rectangle",
        "音乐阅读": "music.note", "购物生活": "bag", "出行旅游": "location",
        "办公学习": "folder", "浏览器网盘": "globe", "金融理财": "chart.line.uptrend.xyaxis",
        "游戏运动": "gamecontroller", "摄影工具": "camera"
    ]

    var body: some View {
        Image(systemName: Self.symbols[category ?? ""] ?? "app")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(ManagementStyle.mint)
            .frame(width: 38, height: 38)
            .background(ManagementStyle.surface, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}
