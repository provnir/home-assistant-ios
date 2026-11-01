import SwiftUI
import UIKit

/// A transparent, touch-transparent UIKit view filling the drawer: it hands `KhalaDrawer` the view to install its pan
/// on (the controller hosting the shell), the drawer's width and layout direction, and the coordinate space every
/// drawer measurement is taken in (it never moves with the card).
struct KhalaDrawerAnchor: UIViewRepresentable {
    let drawer: KhalaDrawer

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.drawer = drawer
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.drawer = drawer
        view.isRightToLeft = context.environment.layoutDirection == .rightToLeft
        view.setNeedsLayout()
    }

    final class AnchorView: UIView {
        weak var drawer: KhalaDrawer?
        var isRightToLeft = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            drawer?.install(anchor: self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            drawer?.layout(width: bounds.width, rightToLeft: isRightToLeft)
        }
    }
}

#Preview {
    KhalaDrawerAnchor(drawer: KhalaDrawer())
}
