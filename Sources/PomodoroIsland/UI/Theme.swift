import SwiftUI

/// 视觉主题
enum Theme {
    /// 岛屿本体：纯黑，与物理刘海融为一体
    static let islandColor = Color.black
    /// 展开后的卡片
    static let cardColor = Color(nsColor: NSColor(calibratedWhite: 0.09, alpha: 0.96))
    static let cardBorder = Color.white.opacity(0.10)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)

    static func accent(for phase: Phase) -> Color {
        switch phase {
        case .focus: return Color(red: 1.0, green: 0.42, blue: 0.34)   // 番茄红
        case .shortBreak: return Color(red: 0.19, green: 0.72, blue: 0.78) // 青
        case .longBreak: return Color(red: 0.49, green: 0.42, blue: 0.95)  // 紫
        case .idle: return Color.white.opacity(0.7)
        }
    }
}

/// 展开面板的圆角卡片
struct CardShape: Shape {
    var radius: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
    }
}
