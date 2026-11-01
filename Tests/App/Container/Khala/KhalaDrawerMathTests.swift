import Foundation
@testable import HomeAssistant
import Testing

struct KhalaDrawerMathTests {
    private let open = 312.0

    @Test func geometry() {
        #expect(KhalaDrawerMath.openWidth(container: 390) == 312)
        #expect(KhalaDrawerMath.openWidth(container: 1024) == 360)
        #expect(KhalaDrawerMath.openWidth(container: -10) == 0)
        #expect(KhalaDrawerMath.progress(position: 156, openWidth: open) == 0.5)
        #expect(KhalaDrawerMath.progress(position: 340, openWidth: open) == 1)
        #expect(KhalaDrawerMath.progress(position: -5, openWidth: open) == 0)
        #expect(KhalaDrawerMath.progress(position: 10, openWidth: 0) == 0)
    }

    @Test func cornersAndShadowFollowProgress() {
        #expect(KhalaDrawerMath.cornerRadius(progress: 0) == 0)
        #expect(KhalaDrawerMath.cornerRadius(progress: 0.125) == 22)
        #expect(KhalaDrawerMath.cornerRadius(progress: 0.25) == 44)
        #expect(KhalaDrawerMath.cornerRadius(progress: 1) == 44)
        #expect(KhalaDrawerMath.shadowOpacity(progress: 0) == 0)
        #expect(abs(KhalaDrawerMath.shadowOpacity(progress: 0.125) - 0.08) < 1e-9)
        #expect(KhalaDrawerMath.shadowOpacity(progress: 0.9) == 0.16)
    }

    @Test func edgeZoneFollowsLayoutDirection() {
        #expect(KhalaDrawerMath.isInEdgeZone(x: 12, width: 390, rightToLeft: false))
        #expect(KhalaDrawerMath.isInEdgeZone(x: 30, width: 390, rightToLeft: false))
        #expect(!KhalaDrawerMath.isInEdgeZone(x: 31, width: 390, rightToLeft: false))
        #expect(!KhalaDrawerMath.isInEdgeZone(x: 12, width: 390, rightToLeft: true))
        #expect(KhalaDrawerMath.isInEdgeZone(x: 375, width: 390, rightToLeft: true))
    }

    @Test func allowedDirectionFromRest() {
        #expect(KhalaDrawerMath.allowedDirection(position: 0, openWidth: open, isSettling: false) == .open)
        #expect(KhalaDrawerMath.allowedDirection(position: open, openWidth: open, isSettling: false) == .close)
        #expect(KhalaDrawerMath.allowedDirection(position: 330, openWidth: open, isSettling: false) == .close)
        #expect(KhalaDrawerMath.allowedDirection(position: 120, openWidth: open, isSettling: false) == .either)
        #expect(KhalaDrawerMath.allowedDirection(position: 0, openWidth: open, isSettling: true) == .either)
    }

    @Test func directionIsDecidedByConeAndSign() {
        // Mostly horizontal toward open: claimed when closed.
        #expect(KhalaDrawerMath.claims(dx: 10, dy: 3, allowed: .open, inEdgeZone: false))
        // Wrong way: refused (the old drawer claimed it).
        #expect(!KhalaDrawerMath.claims(dx: -10, dy: 0, allowed: .open, inEdgeZone: false))
        #expect(!KhalaDrawerMath.claims(dx: 10, dy: 0, allowed: .close, inEdgeZone: false))
        #expect(KhalaDrawerMath.claims(dx: -10, dy: 2, allowed: .close, inEdgeZone: false))
        // ~45°: outside the body cone (35°), inside the edge cone (50°).
        #expect(!KhalaDrawerMath.claims(dx: 10, dy: 10, allowed: .open, inEdgeZone: false))
        #expect(KhalaDrawerMath.claims(dx: 10, dy: 10, allowed: .open, inEdgeZone: true))
        #expect(!KhalaDrawerMath.claims(dx: 10, dy: 13, allowed: .open, inEdgeZone: true))
        // A vertical drag is never the drawer's.
        #expect(!KhalaDrawerMath.claims(dx: 0, dy: 10, allowed: .either, inEdgeZone: true))
        #expect(KhalaDrawerMath.claims(dx: -8, dy: 1, allowed: .either, inEdgeZone: false))
    }

    @Test func trackingIsOneToOneThenRubberBands() {
        #expect(KhalaDrawerMath.trackedPosition(raw: -40, openWidth: open) == 0)
        #expect(KhalaDrawerMath.trackedPosition(raw: 100, openWidth: open) == 100)
        #expect(KhalaDrawerMath.trackedPosition(raw: open, openWidth: open) == open)
        let past = KhalaDrawerMath.trackedPosition(raw: open + 100, openWidth: open)
        #expect(past > open && past < open + KhalaDrawerMath.rubberBandLimit)
        // Gentle at first (slope 0.55), and it never reaches the limit.
        #expect(abs(KhalaDrawerMath.rubberBand(1) - 0.55) < 0.01)
        #expect(KhalaDrawerMath.rubberBand(10000) < KhalaDrawerMath.rubberBandLimit)
        // Monotonic.
        #expect(KhalaDrawerMath.rubberBand(50) < KhalaDrawerMath.rubberBand(51))
    }

    @Test(arguments: [0.0, 80, 312, 330, 360])
    func grabbingMidStretchKeepsThePlace(position: Double) {
        let raw = KhalaDrawerMath.rawPosition(position: position, openWidth: open)
        #expect(abs(KhalaDrawerMath.trackedPosition(raw: raw, openWidth: open) - position) < 1e-6)
    }

    @Test func projectionMatchesApple() {
        // (v/1000)·0.998/0.002 = 0.499·v
        #expect(abs(KhalaDrawerMath.projection(velocity: 1000) - 499) < 1e-6)
        #expect(abs(KhalaDrawerMath.projection(velocity: -400) + 199.6) < 1e-6)
        #expect(KhalaDrawerMath.projection(velocity: 0) == 0)
    }

    @Test func releaseDecision() {
        // Slow: the projected midpoint decides.
        #expect(KhalaDrawerMath.opensAfterRelease(position: 160, velocity: 0, openWidth: open))
        #expect(!KhalaDrawerMath.opensAfterRelease(position: 150, velocity: 0, openWidth: open))
        #expect(KhalaDrawerMath.opensAfterRelease(position: 120, velocity: 100, openWidth: open))
        #expect(!KhalaDrawerMath.opensAfterRelease(position: 190, velocity: -100, openWidth: open))
        // A decisive velocity is never settled against, however far the card is.
        #expect(KhalaDrawerMath.opensAfterRelease(position: 10, velocity: 150, openWidth: open))
        #expect(!KhalaDrawerMath.opensAfterRelease(position: 300, velocity: -150, openWidth: open))
        #expect(!KhalaDrawerMath.opensAfterRelease(position: 340, velocity: -2000, openWidth: open))
        // A slow close from fully open stays open (the old 60 pt rule snapped it shut).
        #expect(KhalaDrawerMath.opensAfterRelease(position: 240, velocity: -60, openWidth: open))
    }

    @Test func bounceOnlyOnAFastOpenFlick() {
        #expect(KhalaDrawerMath.settleBounce(opens: true, velocity: 900) == KhalaDrawerMath.flickBounce)
        #expect(KhalaDrawerMath.settleBounce(opens: true, velocity: 400) == 0)
        #expect(KhalaDrawerMath.settleBounce(opens: false, velocity: -3000) == 0)
    }

    @Test func backSwipe() {
        #expect(KhalaDrawerMath.goesBack(travel: 100, velocity: 0))
        #expect(!KhalaDrawerMath.goesBack(travel: 40, velocity: 0))
        #expect(KhalaDrawerMath.goesBack(travel: 20, velocity: 300))
        // Pulled back at the end: no.
        #expect(!KhalaDrawerMath.goesBack(travel: 200, velocity: -400))
    }
}
