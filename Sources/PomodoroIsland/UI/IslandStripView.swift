import SwiftUI

/// 刘海条（岛屿本体）：顶部直角与屏幕顶/物理刘海融合，底部圆角"下巴"承载内容。
/// 物理刘海区域本身无法显示像素，所有内容都画在刘海下方的延伸区。
struct IslandStripView: View {

    @EnvironmentObject private var engine: PomodoroEngine
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var controller: NotchWindowController

    private var notchHeight: CGFloat {
        NotchScreenInfo.notchSize(on: NotchScreenInfo.preferredScreen()).height
    }

    private var extensionHeight: CGFloat {
        controller.isExpanded
            ? NotchScreenInfo.expandedExtension
            : NotchScreenInfo.collapsedExtension
    }

    private var totalHeight: CGFloat { notchHeight + extensionHeight }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 18,
            bottomTrailingRadius: 18,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape
                .fill(Theme.islandColor)
                .overlay(shape.strokeBorder(Theme.cardBorder, lineWidth: 0.5))

            if controller.isExpanded {
                expandedHeader
                    .padding(.top, notchHeight + 6)
                    .transition(.opacity)
            } else {
                collapsedContent
                    .padding(.top, notchHeight + 2)
                    .transition(.opacity)
            }
        }
        .frame(height: totalHeight)
        .contentShape(shape)
        .onTapGesture {
            // 展开态点岛屿头部收起（收起态由全局点击监听负责展开）
            if controller.isExpanded {
                controller.collapse()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controller.isExpanded)
    }

    // MARK: - 收起态（内容位于刘海下方的 24pt 下巴内）

    private var collapsedContent: some View {
        HStack(spacing: 6) {
            phaseDot

            Text(engine.displayText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            if !engine.running, store.todayFocusCount > 0 {
                Text("🍅×\(store.todayFocusCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: NotchScreenInfo.collapsedExtension - 4, alignment: .center)
    }

    private var phaseDot: some View {
        Circle()
            .fill(Theme.accent(for: engine.phase))
            .frame(width: 7, height: 7)
            .opacity(engine.running ? 1 : 0.55)
    }

    // MARK: - 展开态头部（位于刘海下方的 44pt 延伸区）

    private var expandedHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: engine.phase.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent(for: engine.phase))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(store.currentTask?.title ?? "未选择任务")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(engine.phase.label) · 今日 \(store.todayFocusCount) 🍅")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 8)

            Text(engine.displayText)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 16)
        .frame(height: NotchScreenInfo.expandedExtension - 8, alignment: .center)
    }
}
