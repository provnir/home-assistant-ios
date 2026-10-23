import Foundation

/// The zoom rules of the live player and the still viewer. The zoom itself is a `UIScrollView` around the content
/// (`KhalaZoomContainer`: the web view for live, an image view for a still): pinch, pan, momentum, edge
/// rubber-banding and the bounce back past the limits all run in UIKit and Core Animation on the render server, with
/// no round trip into the page. These are only the choices around it.
enum KhalaLiveZoom {
    static let minimum: CGFloat = 1
    static let maximum: CGFloat = 4
    /// Double tap walks 1× → 2.5× → 4× → 1×.
    static let steps: [CGFloat] = [1, 2.5, 4]
    /// Below this the picture counts as unzoomed (no chip, panning off, swipe-down allowed).
    static let threshold: CGFloat = 1.02

    static func isZoomed(_ scale: CGFloat) -> Bool {
        scale >= threshold
    }

    /// The next double-tap step after `scale`: the first step clearly above it, else back to 1×. A pinch to 3×
    /// goes on to 4×; one at 4× (or past it, mid-bounce) goes home.
    static func nextStep(after scale: CGFloat) -> CGFloat {
        steps.first { $0 > scale + 0.05 } ?? minimum
    }

    /// The rectangle (in the unzoomed content's coordinates) that `UIScrollView.zoom(to:animated:)` should show to
    /// land on `scale` centred on `point`, kept inside the content so the zoom never lands past an edge.
    static func zoomRect(scale: CGFloat, center point: CGPoint, in size: CGSize) -> CGRect {
        let scale = min(max(scale, minimum), maximum)
        let width = size.width / scale
        let height = size.height / scale
        let x = min(max(point.x - width / 2, 0), max(size.width - width, 0))
        let y = min(max(point.y - height / 2, 0), max(size.height - height, 0))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The chip's text: "2.5×", "4×", "1.8×"; `nil` when unzoomed.
    static func label(_ scale: CGFloat) -> String? {
        guard isZoomed(scale) else { return nil }
        let tenths = (Double(scale) * 10).rounded()
        if tenths.truncatingRemainder(dividingBy: 10) == 0 {
            return "\(Int(tenths / 10))×"
        }
        return String(format: "%.1f×", tenths / 10)
    }

    /// A still's unzoomed size: `aspect` (the image's own size) fitted inside `bounds`, as `.scaleAspectFit` draws it.
    /// The zoom works on that rectangle, not the whole screen, so a zoomed still pans to its own edges and never
    /// into the letterbox around it. An empty aspect fills the bounds.
    static func fittedSize(_ aspect: CGSize, in bounds: CGSize) -> CGSize {
        guard aspect.width > 0, aspect.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        // Wider than the bounds: full width, letterboxed; otherwise full height, pillarboxed.
        if aspect.width * bounds.height > aspect.height * bounds.width {
            return CGSize(width: bounds.width, height: bounds.width * aspect.height / aspect.width)
        }
        return CGSize(width: bounds.height * aspect.width / aspect.height, height: bounds.height)
    }

    /// The inset on each side that keeps zoomed content of `size` centred in `bounds` while it is smaller than them
    /// along an axis (the still's letterbox at 1×, shrinking as it zooms); zero once it fills that axis.
    static func centringInset(content size: CGSize, in bounds: CGSize) -> CGSize {
        CGSize(width: max((bounds.width - size.width) / 2, 0), height: max((bounds.height - size.height) / 2, 0))
    }

    /// Full screen's swipe down: past a third of 300 pt, or a downward flick.
    static func shouldDismiss(translation: CGFloat, velocity: CGFloat) -> Bool {
        translation > 100 || (translation > 20 && velocity > 800)
    }

    /// How far a swipe down has gone, 0...1, for fading the backdrop while the picture follows the finger.
    static func dismissProgress(translation: CGFloat, height: CGFloat) -> CGFloat {
        guard height > 0 else { return 0 }
        return min(max(translation / (height * 0.5), 0), 1)
    }
}
