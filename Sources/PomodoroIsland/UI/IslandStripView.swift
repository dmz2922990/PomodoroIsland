import SwiftUI

/// 刘海条（岛屿本体）：收起时显示紧凑计时，展开时变成面板头
struct IslandStripView: View {

    @EnvironmentObject private var engine: PomodoroEngine
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var controller: NotchWindowController

    var body: some View {
        ZStack {
            IslandShape()
                .fill(Theme.islandColor)
                .overlay(
                    IslandShape()
                        .stroke(Theme.cardBorder, lineWidth: 0.5)
                )

            if controller.isExpanded {
                expandedHeader
            } else {
                collapsedContent
            }
        }
        .frame(height: stripHeight)
        .contentShape(IslandShape())
        .onTapGesture {
            // 展开态点岛屿头部收起（收起态由全局点击监听负责展开）
            if controller.isExpanded {
                controller.collapse()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controller.isExpanded)
    }

    private var stripHeight: CGFloat {
        NotchScreenInfo.notchSize(on: NotchScreenInfo.preferredScreen()).height
    }

    // MARK: - 收起态

    private var collapsedContent: some View {
        HStack(spacing: 6) {
            phaseDot

            Text(engine.displayText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            if !engine.running, phaseDotBlink {
                Text("🍅×\(store.todayFocusCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
    }

    private var phaseDotBlink: Bool { store.todayFocusCount > 0 }

    private var phaseDot: some View {
        Circle()
            .fill(Theme.accent(for: engine.phase))
            .frame(width: 7, height: 7)
            .opacity(engine.running ? 1 : 0.55)
    }

    // MARK: - 展开态头部

    private var expandedHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: engine.phase.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent(for: engine.phase))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 0) {
                Text(store.currentTask?.title ?? "未选择任务")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(engine.phase.label + " · 今日 \(store.todayFocusCount) 🍅")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 8)

            Text(engine.displayText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 14)
    }
}
