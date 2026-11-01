import SwiftUI

/// The moving half of the drawer: the screen card and its edge shadow, offset by `KhalaDrawer.position`. The only
/// views (with `KhalaDrawerRounding`) that observe the drawer, so a frame of motion re-renders this wrapper, never
/// the shell; `content` is built by the shell and passed through unchanged.
struct KhalaDrawerStage<Content: View>: View {
    @ObservedObject var drawer: KhalaDrawer
    let content: Content

    @Environment(\.layoutDirection) private var layoutDirection

    init(drawer: KhalaDrawer, @ViewBuilder content: () -> Content) {
        self.drawer = drawer
        self.content = content()
    }

    var body: some View {
        let sign: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
        let progress = drawer.progress
        ZStack(alignment: .topLeading) {
            // The card's edge shadow, on a plain shape so the moving card itself is never shadowed.
            RoundedRectangle(cornerRadius: CGFloat(KhalaDrawerMath.cornerRadius(progress: progress)), style: .continuous)
                .fill(KhalaTheme.groundFlat)
                .shadow(
                    color: KhalaTheme.shadow.opacity(KhalaDrawerMath.shadowOpacity(progress: progress)),
                    radius: 13,
                    x: -6 * sign,
                    y: 2
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            content
        }
        // Toward the trailing side (same sign convention the shell has always used for right-to-left).
        .offset(x: drawer.position * sign)
    }
}

#Preview {
    KhalaDrawerStage(drawer: KhalaDrawer()) {
        Color.white
    }
    .background(Color.gray)
}
