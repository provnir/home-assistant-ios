import Foundation

/// Geometry, gesture and release rules of the menu drawer (the screen card slides aside over a static menu panel).
/// The interaction follows DRAWER-RESEARCH §6: the direction is decided once at the touch slop, the card tracks the
/// finger 1:1 (rubber-banding past open, clamped at closed), the release is projected with Apple's deceleration and
/// settled by a spring that starts at the finger's velocity.
///
/// All values in points (and points per second). "Position" is how far the card has moved aside toward open:
/// 0 closed, `openWidth` open. Signed values (`dx`, `velocity`, `travel`) are already flipped for right-to-left
/// layouts, so positive always means "toward open".
enum KhalaDrawerMath {
    // MARK: Geometry

    static let openFraction = 0.8
    static let maximumOpenWidth = 360.0
    /// Width of the leading-edge zone that opens the drawer over the web UI (anywhere works on native screens).
    static let edgeWidth = 30.0
    /// Corner radius of the moved-aside card, as in the design (44 pt).
    static let cardRadius = 44.0
    /// The card's edge shadow at full strength.
    static let shadowOpacity = 0.16

    static func openWidth(container: Double) -> Double {
        min(max(0, container) * openFraction, maximumOpenWidth)
    }

    /// 0 = closed, 1 = open (clamped: a rubber-banded card reads as open).
    static func progress(position: Double, openWidth: Double) -> Double {
        guard openWidth > 0 else { return 0 }
        return min(1, max(0, position / openWidth))
    }

    /// The card's corner radius: rounds in over the first quarter of the travel.
    static func cornerRadius(progress: Double) -> Double {
        cardRadius * ramp(progress)
    }

    /// The card's edge shadow opacity: fades in over the first quarter of the travel, like the corners.
    static func shadowOpacity(progress: Double) -> Double {
        shadowOpacity * ramp(progress)
    }

    private static func ramp(_ progress: Double) -> Double {
        min(1, max(0, progress) * 4)
    }

    // MARK: Where a drag may start

    /// Whether a touch at `x` (in the drawer's own width) is in the leading-edge zone.
    static func isInEdgeZone(x: Double, width: Double, rightToLeft: Bool) -> Bool {
        rightToLeft ? x >= width - edgeWidth : x <= edgeWidth
    }

    /// Which way a drag may move the card, decided at touch-down: from rest only toward the other state; while the
    /// card is between the two (settling, or grabbed mid-way), either way.
    enum Direction: Equatable {
        case open
        case close
        case either
    }

    static func allowedDirection(position: Double, openWidth: Double, isSettling: Bool) -> Direction {
        if isSettling { return .either }
        if position <= 0.5 { return .open }
        if position >= openWidth - 0.5 { return .close }
        return .either
    }

    /// The direction cone: `|dy| ≤ cone·|dx|`. About ±35° on the body, ±50° inside the edge zone.
    static let bodyCone = 0.7
    static let edgeCone = 1.2

    /// Whether the drawer claims a drag, decided ONCE when the finger has moved past the touch slop: mostly
    /// horizontal (inside the cone) AND pointing the allowed way. A refused drag stays refused for that touch (the
    /// recognizer fails).
    static func claims(dx: Double, dy: Double, allowed: Direction, inEdgeZone: Bool) -> Bool {
        let horizontal = abs(dx)
        guard horizontal > 0 else { return false }
        let cone = inEdgeZone ? edgeCone : bodyCone
        guard abs(dy) <= cone * horizontal else { return false }
        switch allowed {
        case .open: return dx > 0
        case .close: return dx < 0
        case .either: return true
        }
    }

    // MARK: Tracking

    /// How far past open the card may stretch at most (the rubber band's asymptote).
    static let rubberBandLimit = 60.0
    /// UIScrollView's rubber-band constant (community reverse-engineered).
    static let rubberBandFactor = 0.55

    /// Where the card shows for a raw finger position `raw` (start + translation): 1:1 between closed and open,
    /// rubber-banded past open, clamped at closed.
    static func trackedPosition(raw: Double, openWidth: Double) -> Double {
        if raw <= 0 { return 0 }
        guard raw > openWidth else { return raw }
        return openWidth + rubberBand(raw - openWidth)
    }

    /// The raw finger position that shows the card at `position`, so a card grabbed mid-stretch keeps its place.
    static func rawPosition(position: Double, openWidth: Double) -> Double {
        guard position > openWidth else { return max(0, position) }
        return openWidth + inverseRubberBand(position - openWidth)
    }

    /// `d·(1 − 1/(x·c/d + 1))`: starts 1:1-ish (slope `c`), never reaches `d`.
    static func rubberBand(_ excess: Double) -> Double {
        let d = rubberBandLimit
        guard excess > 0 else { return 0 }
        return d * (1 - 1 / (excess * rubberBandFactor / d + 1))
    }

    static func inverseRubberBand(_ stretch: Double) -> Double {
        let d = rubberBandLimit
        guard stretch > 0 else { return 0 }
        let y = min(stretch, d * 0.999)
        return d / rubberBandFactor * (1 / (1 - y / d) - 1)
    }

    // MARK: Release

    /// UIScrollView's normal deceleration rate.
    static let decelerationRate = 0.998
    /// A release at least this fast is never settled against its direction.
    static let decisiveVelocity = 150.0
    /// A release toward open at least this fast is a flick, rewarded with a little bounce.
    static let flickVelocity = 800.0
    static let flickBounce = 0.08

    /// Apple's projection (WWDC18 *Designing Fluid Interfaces*): how far momentum carries a release,
    /// `(v/1000)·r/(1−r)`, about `0.5·v` at the normal rate.
    static func projection(velocity: Double, decelerationRate: Double = decelerationRate) -> Double {
        (velocity / 1000) * decelerationRate / (1 - decelerationRate)
    }

    /// Whether the drawer settles open: never against a decisive velocity; otherwise open when the projected
    /// position is at least half the width.
    static func opensAfterRelease(position: Double, velocity: Double, openWidth: Double) -> Bool {
        if velocity >= decisiveVelocity { return true }
        if velocity <= -decisiveVelocity { return false }
        return position + projection(velocity: velocity) >= openWidth / 2
    }

    /// The settle spring's bounce: a little on a fast flick to open, none otherwise (closing never bounces: an
    /// overshoot past closed would show the menu's edge on the other side).
    static func settleBounce(opens: Bool, velocity: Double) -> Double {
        opens && velocity >= flickVelocity ? flickBounce : 0
    }

    /// The settle spring's duration (SwiftUI's `.spring(duration: 0.38, bounce: 0)`).
    static let settleDuration = 0.38
    /// A menu button or selection with Reduce Motion on: short, no bounce.
    static let reducedMotionDuration = 0.25

    // MARK: Back (the web UI's sub-page or dialog)

    /// How far (projected) an edge swipe must go to count as Back.
    static let backDistance = 90.0

    /// Whether an edge swipe over a web sub-page or dialog goes Back on release: far enough once projected, and not
    /// pulled back at the end.
    static func goesBack(travel: Double, velocity: Double) -> Bool {
        guard velocity > -decisiveVelocity else { return false }
        return travel + projection(velocity: velocity) >= backDistance
    }
}
