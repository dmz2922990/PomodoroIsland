import AppKit

/// 番茄生长/腐烂精灵帧库（由 Icon.png 切割，位于 Bundle 资源 Icon/frames/）
enum IconLibrary {

    /// 成长序列：小苗 → 开花 → 绿果 → 转红 → 红果
    static let growth: [NSImage] = loadFrames(prefix: "growth")

    /// 腐烂序列：红斑 → 塌烂 → 化为泥土
    static let rot: [NSImage] = loadFrames(prefix: "rot")

    /// 空闲（待开始）状态：一块未播种的土
    static let wait: NSImage? = Bundle.module
        .url(forResource: "wait", withExtension: "png", subdirectory: "frames")
        .flatMap(NSImage.init(contentsOf:))

    /// 无任务时的绿色小苗
    static var sprout: NSImage? { growth.first }

    private static func loadFrames(prefix: String) -> [NSImage] {
        // SPM .copy("Icon/frames") 在 bundle 内平铺为 frames/
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "png", subdirectory: "frames") else {
            NSLog("PomodoroIsland IconLibrary: bundle frames not found")
            return []
        }
        return urls
            .filter { $0.lastPathComponent.hasPrefix(prefix + "-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { NSImage(contentsOf: $0) }
    }
}
