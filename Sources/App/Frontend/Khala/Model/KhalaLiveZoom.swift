import Foundation

/// The live player's zoom rules. The zoom itself is a `UIScrollView` around the web view (`KhalaLiveZoomView`):
/// pinch, pan, momentum, edge rubber-banding and the bounce back past the limits all run in UIKit and Core
/// Animation on the render server, with no round trip into the page. These are only the choices around it.
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
