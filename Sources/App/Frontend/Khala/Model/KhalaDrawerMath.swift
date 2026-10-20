import Foundation

/// Geometry and release rules of the menu drawer (the screen card slides aside over a static menu panel),
/// following the Zoe app's phone drawer (`DrawerInteraction`/`DrawerMotion` in provnir/Zoe): panel at ~80% of
/// the width capped at 360 pt, release decided by flick first, then distance, else back where it was.
/// All values in points; "travel" is signed toward opening (already flipped for right-to-left layouts).
enum KhalaDrawerMath {
    static let openFraction = 0.8
    static let maximumOpenWidth = 360.0
    /// A release that would carry this much further on its own momentum counts as a flick.
    static let flickProjection = 120.0
    /// Without a flick, a drag this long decides the direction.
    static let decidingTravel = 60.0
    /// Width of the leading-edge strip that starts an opening swipe.
    static let edgeWidth = 20.0
    /// Settle curve: cubic-bezier(0.25, 1, 0.5, 1) over 0.31 s (Zoe's `DrawerMotion.settle`).
    static let settleDuration = 0.31
    static let settleControlPoints = (x1: 0.25, y1: 1.0, x2: 0.5, y2: 1.0)
    /// Corner radius of the moved-aside card, as in the design (44 pt).
    static let cardRadius = 44.0

    static func openWidth(container: Double) -> Double {
        min(max(0, container) * openFraction, maximumOpenWidth)
    }

    /// 0 = closed, 1 = open, following a drag in progress.
    static func progress(isOpen: Bool, travel: Double, openWidth: Double) -> Double {
        guard openWidth > 0 else { return isOpen ? 1 : 0 }
        let base = isOpen ? openWidth : 0
        return min(1, max(0, (base + travel) / openWidth))
    }

    /// Whether the drawer should end open. `projectedTravel` is where the drag would end with momentum
    /// (`DragGesture.Value.predictedEndTranslation`, sign-corrected).
    static func opensAfterRelease(wasOpen: Bool, travel: Double, projectedTravel: Double) -> Bool {
        let momentum = projectedTravel - travel
        if abs(momentum) > flickProjection { return momentum > 0 }
        if abs(travel) > decidingTravel { return travel > 0 }
        return wasOpen
    }

    /// The card's corner radius while it moves: rounds in over the first quarter of the travel.
    static func cornerRadius(progress: Double) -> Double {
        cardRadius * min(1, max(0, progress) * 4)
    }
}
