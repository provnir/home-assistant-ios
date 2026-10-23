import SFSafeSymbols
import SwiftUI
import UIKit

/// `KhalaStillPager` in SwiftUI: the still viewer's zoomable pages.
struct KhalaStillPagerView: UIViewRepresentable {
    let stills: [KhalaStill]
    @Binding var index: Int
    /// Changed by the host to zoom the page on screen back to 1× (the zoom chip).
    var resetToken: Int
    var onTap: () -> Void
    var onZoom: (CGFloat) -> Void
    var onDismissProgress: (CGFloat) -> Void
    var onDismiss: () -> Void

    final class Coordinator {
        var resetToken = 0
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.resetToken = resetToken
        return coordinator
    }

    func makeUIView(context: Context) -> KhalaStillPager {
        let pager = KhalaStillPager()
        configure(pager)
        pager.show(stills, at: index)
        return pager
    }

    func updateUIView(_ pager: KhalaStillPager, context: Context) {
        configure(pager)
        pager.show(stills, at: index)
        if context.coordinator.resetToken != resetToken {
            context.coordinator.resetToken = resetToken
            pager.resetZoom()
        }
    }

    private func configure(_ pager: KhalaStillPager) {
        let index = _index
        pager.onIndex = { index.wrappedValue = $0 }
        pager.onTap = onTap
        pager.onZoom = onZoom
        pager.onDismissProgress = onDismissProgress
        pager.onDismiss = onDismiss
    }
}

#Preview {
    KhalaStillPagerView(
        stills: [
            KhalaStill(id: "a", image: UIImage(systemSymbol: .photo), accessibilityLabel: "Camera, 08:35"),
            KhalaStill(id: "b", image: UIImage(systemSymbol: .photoFill), accessibilityLabel: "Camera, 09:10"),
        ],
        index: .constant(0),
        resetToken: 0,
        onTap: {},
        onZoom: { _ in },
        onDismissProgress: { _ in },
        onDismiss: {}
    )
    .background(Color.black)
}
