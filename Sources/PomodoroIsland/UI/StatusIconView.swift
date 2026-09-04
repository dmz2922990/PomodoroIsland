import SwiftUI
import AppKit

/// 状态图标：像素风番茄。
/// - 无任务/待机/休息：绿色小苗
/// - 专注中：随进度 小苗 → 开花 → 绿果 → 红果
/// - 超时：红果逐渐腐烂 → 化为泥土
struct StatusIconView: View {

    var phase: Phase
    var progress: Double
    var isOvertime: Bool
    var overtimeFraction: Double
    var size: CGFloat

    var body: some View {
        Group {
            if let img = currentImage {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                // 帧库缺失时回退为状态圆点
                Circle().fill(Theme.accent(for: phase)).opacity(0.85)
            }
        }
        // 底部对齐：所有帧共享同一条"地面线"（空闲的土块与生长帧的土面齐平）
        .frame(width: size, height: size, alignment: .bottom)
    }

    private var currentImage: NSImage? {
        guard phase == .focus || isOvertime else {
            // 空闲：未播种的土；休息：小苗
            if phase == .idle { return IconLibrary.wait ?? IconLibrary.sprout }
            return IconLibrary.sprout
        }
        let frames = isOvertime ? IconLibrary.rot : IconLibrary.growth
        guard !frames.isEmpty else { return IconLibrary.sprout }
        let fraction = isOvertime ? overtimeFraction : progress
        let idx = min(frames.count - 1, Int(fraction * Double(frames.count)))
        return frames[idx]
    }
}
