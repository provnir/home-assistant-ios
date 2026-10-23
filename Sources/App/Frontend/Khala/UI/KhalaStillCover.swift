import SFSafeSymbols
import SwiftUI
import UIKit

extension View {
    /// Presents the still viewer for `item` over everything, as UIKit's `.overFullScreen` (the camera overlay's own
    /// style, `CameraOverlayPresenter`), fading in. Not SwiftUI's `fullScreenCover`: that is `.fullScreen`, which
    /// takes the presenting view off screen and fires its `onDisappear` (see `CameraOverlayHostingController`), so a
    /// snapshot opened from a live player would stop its stream and the shell's would stop its updates. Over full
    /// screen the presenter stays where it is, and shows through while the viewer is swiped away.
    ///
    /// The viewer is built once per item (by id) and closes when `item` goes back to `nil`; it gets none of the
    /// presenter's environment, so everything it needs is passed in.
    func khalaStillCover<Item: Identifiable, Cover: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Cover
    ) -> some View {
        background(KhalaStillCover(item: item, content: content).frame(width: 0, height: 0))
    }
}

/// The zero-size anchor `khalaStillCover(item:content:)` presents from.
struct KhalaStillCover<Item: Identifiable, Cover: View>: UIViewControllerRepresentable {
    @Binding var item: Item?
    let content: (Item) -> Cover

    final class Coordinator {
        weak var presented: Host?
        var presentedId: AnyHashable?
    }

    /// The viewer's controller: light status bar text over black, and a note when UIKit has taken it down.
    final class Host: UIHostingController<AnyView> {
        var onDismissed: (() -> Void)?

        override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if isBeingDismissed || presentingViewController == nil { onDismissed?() }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let anchor = UIViewController()
        anchor.view.isUserInteractionEnabled = false
        return anchor
    }

    func updateUIViewController(_ anchor: UIViewController, context: Context) {
        let coordinator = context.coordinator
        guard let item else {
            if let presented = coordinator.presented {
                coordinator.presented = nil
                coordinator.presentedId = nil
                presented.dismiss(animated: true)
            }
            return
        }
        guard coordinator.presentedId != AnyHashable(item.id) else { return }
        coordinator.presented?.dismiss(animated: false)

        let host = Host(rootView: AnyView(content(item)))
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .crossDissolve
        host.modalPresentationCapturesStatusBarAppearance = true
        host.view.backgroundColor = .clear
        let binding = $item
        let id = AnyHashable(item.id)
        host.onDismissed = { [weak coordinator] in
            // Taken down by UIKit rather than by the binding: let the host know it is closed.
            guard let coordinator, coordinator.presentedId == id else { return }
            coordinator.presented = nil
            coordinator.presentedId = nil
            if binding.wrappedValue.map({ AnyHashable($0.id) }) == id { binding.wrappedValue = nil }
        }
        coordinator.presented = host
        coordinator.presentedId = id

        // From whatever is already presented on top of this screen (a sheet, the camera overlay).
        var presenter = anchor
        while let next = presenter.presentedViewController, !next.isBeingDismissed {
            presenter = next
        }
        presenter.present(host, animated: true)
    }

    static func dismantleUIViewController(_ anchor: UIViewController, coordinator: Coordinator) {
        coordinator.presented?.dismiss(animated: false)
        coordinator.presented = nil
        coordinator.presentedId = nil
    }
}

#Preview {
    let snapshot = KhalaSnapshot(image: UIImage(systemSymbol: .photo), cameraName: "Camera")
    Text(verbatim: "Screen")
        .khalaStillCover(item: .constant(snapshot)) {
            KhalaSnapshotViewer(snapshot: $0, onClose: {})
        }
}
