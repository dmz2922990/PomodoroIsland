import SwiftUI

/// 刘海窗口的根视图：顶部岛屿 + 展开后的面板
struct NotchRootView: View {

    @EnvironmentObject private var controller: NotchWindowController

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 6) {
                IslandStripView()

                if controller.isExpanded {
                    PanelView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                            removal: .opacity
                        ))
                }
            }
            .padding(.bottom, 8)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: controller.isExpanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
