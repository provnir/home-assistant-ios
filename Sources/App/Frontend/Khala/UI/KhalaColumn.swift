import SwiftUI

extension View {
    /// Holds a native screen's content to a centred column in a regular width (iPhone Duo's inner display, iPad,
    /// a wide Split View pane) and leaves it untouched in a compact width (`KhalaColumnMath`). Apply it outside the
    /// content's own gutters, inside its scroll view, so the scroll view (and the ground behind it) stays full width
    /// and scrolls from anywhere.
    func khalaColumn(_ kind: KhalaColumnMath.Kind = .readable) -> some View {
        modifier(KhalaColumnModifier(kind: kind))
    }
}

private struct KhalaColumnModifier: ViewModifier {
    let kind: KhalaColumnMath.Kind
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        if let width = KhalaColumnMath.maximumWidth(kind: kind, isRegularWidth: horizontalSizeClass == .regular) {
            content
                .frame(maxWidth: CGFloat(width), alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            content
        }
    }
}
