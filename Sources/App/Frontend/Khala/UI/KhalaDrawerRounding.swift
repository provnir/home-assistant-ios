import SwiftUI

/// Rounds a native screen card's corners as the drawer moves (the web card is rounded on its UIKit layer instead,
/// `KhalaShellModel.applyFrontendCorners`). The mask reaches the display's edges, so the ground (and content scrolled
/// under the bars) shows behind the status bar and the home indicator, and the rounded corners land on the display's
/// own corners; a plain `clipShape` would cut the screen back to the safe area.
struct KhalaDrawerRounding<Content: View>: View {
    @ObservedObject var drawer: KhalaDrawer
    let content: Content

    init(drawer: KhalaDrawer, @ViewBuilder content: () -> Content) {
        self.drawer = drawer
        self.content = content()
    }

    var body: some View {
        let radius = CGFloat(KhalaDrawerMath.cornerRadius(progress: drawer.progress))
        content
            .mask {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .ignoresSafeArea()
            }
    }
}

#Preview {
    KhalaDrawerRounding(drawer: KhalaDrawer()) {
        Color.white
    }
}
