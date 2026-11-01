import SwiftUI
import UIKit

/// The menu drawer's motion and its one gesture (DRAWER-RESEARCH §6). SwiftUI lays the shell out; this object moves
/// the card:
///
/// - ONE plain `UIPanGestureRecognizer`, installed on the UIKit view that hosts the whole shell (found from
///   `KhalaDrawerAnchor`), so it sees touches on the native screens, the menu, the stand-by screen and the web view
///   alike, and negotiates with their recognizers through its delegate. The web frontend itself is never moved,
///   re-parented or rebuilt: its identity stays exactly as SwiftUI built it.
/// - Its direction is decided ONCE at the touch slop (`gestureRecognizerShouldBegin`, `KhalaDrawerMath.claims`); a
///   refused drag fails, and stays failed for that touch. Scroll views' pans (the web view's included) and screen-edge
///   pans wait for that decision (`shouldBeRequiredToFailBy`), so a vertical scroll is never held past the slop.
/// - The card tracks the finger 1:1 from where it is ON SCREEN (rubber-banding past open), and is settled by a
///   closed-form spring (`KhalaDrawerSpring`) sampled once per display frame. The spring starts at the release
///   velocity in pt/s, and grabbing the card mid-settle stops it exactly where it shows.
/// - Only `position` is published, and only `KhalaDrawerStage` / `KhalaDrawerRounding` observe it, so a frame never
///   re-runs the shell's body. `onProgress` lets the web card's UIKit corners follow every frame too.
@MainActor
final class KhalaDrawer: NSObject, ObservableObject {
    /// What the shell is showing, read when a touch lands.
    struct Context {
        /// The web UI is up on the card (Dashboards, connected): opening only from the leading-edge zone.
        var isWebScreen = false
        /// The web UI's header shows Back (sub-page or dialog): the edge swipe goes Back instead of to the menu.
        var showsBack = false
    }

    /// How far the card has moved aside toward open, in points: 0 closed, `openWidth` open, a little more while
    /// rubber-banding or bouncing.
    @Published private(set) var position: CGFloat = 0

    /// The state the drawer rests in, or is settling to.
    private(set) var isOpen = false
    private(set) var openWidth: CGFloat = 0
    private(set) var isRightToLeft = false

    var progress: Double {
        KhalaDrawerMath.progress(position: Double(position), openWidth: Double(openWidth))
    }

    // MARK: Hooks (set by `KhalaShellModel`)

    var context: () -> Context = { Context() }
    /// A drag ended in a different state than it started; the shell's `isMenuOpen` follows.
    var onCommit: (Bool) -> Void = { _ in }
    /// The edge swipe over a web sub-page or dialog.
    var onBack: () -> Void = {}
    /// Every frame the card moves (presented progress 0...1).
    var onProgress: (Double) -> Void = { _ in }
    /// Controllers whose presentations block the drawer besides the host's own chain (the web view's controller,
    /// which the camera player is presented on).
    var extraPresenters: () -> [UIViewController] = { [] }

    // MARK: Gesture

    private let pan = UIPanGestureRecognizer()
    private weak var anchor: UIView?
    private weak var host: UIView?
    private let feedback = UIImpactFeedbackGenerator(style: .light)

    private enum Mode {
        case drawer
        case back
    }

    private var mode: Mode?
    private var touchStart: CGPoint = .zero
    private var trackStart: Double = 0
    private var wasOpenAtBegin = false
    private var keyboardIsVisible = false

    // MARK: Spring

    private var spring: KhalaDrawerSpring?
    private var springStart: CFTimeInterval = 0
    private var displayLink: CADisplayLink?

    var isSettling: Bool { spring != nil }

    override init() {
        super.init()
        pan.addTarget(self, action: #selector(handlePan(_:)))
        pan.delegate = self
        // Default UIKit behaviour, spelled out: when the drawer claims a drag, touches under it are cancelled (a
        // web slider gets `touchcancel`); touches are never delayed, so taps stay instant.
        pan.cancelsTouchesInView = true
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    // MARK: Anchor

    /// Called by `KhalaDrawerAnchor` when it enters or leaves a window: the pan goes on the view of the controller
    /// hosting the shell (an ancestor of every screen, the menu and the web view).
    func install(anchor: UIView) {
        self.anchor = anchor
        guard anchor.window != nil else {
            pan.view?.removeGestureRecognizer(pan)
            host = nil
            return
        }
        var view: UIView? = anchor
        var hostView: UIView = anchor
        while let current = view {
            hostView = current
            if current.next is UIViewController { break }
            view = current.superview
        }
        guard pan.view !== hostView else { return }
        pan.view?.removeGestureRecognizer(pan)
        hostView.addGestureRecognizer(pan)
        host = hostView
    }

    /// The anchor's size and layout direction (it fills the drawer).
    func layout(width: CGFloat, rightToLeft: Bool) {
        isRightToLeft = rightToLeft
        let newWidth = CGFloat(KhalaDrawerMath.openWidth(container: Double(width)))
        guard newWidth != openWidth else { return }
        openWidth = newWidth
        if !isSettling, mode == nil {
            setPosition(isOpen ? openWidth : 0)
        }
    }

    // MARK: Programmatic

    /// Opens or closes with the settle spring (the menu button, a menu selection, `menuRequests`, a route). From
    /// rest it starts at zero velocity; a spring already running hands over its own velocity. Reduce Motion: short,
    /// no bounce.
    func setOpen(_ open: Bool) {
        let target = open ? openWidth : 0
        if open == isOpen {
            if let spring, spring.target == Double(target) { return }
            if spring == nil, mode == nil, position == target { return }
        }
        if mode != nil {
            // A programmatic change wins over a drag in progress (a deep link while the finger is down).
            pan.isEnabled = false
            pan.isEnabled = true
            mode = nil
        }
        isOpen = open
        let duration = UIAccessibility.isReduceMotionEnabled
            ? KhalaDrawerMath.reducedMotionDuration
            : KhalaDrawerMath.settleDuration
        startSpring(to: target, velocity: currentSpringVelocity(), duration: duration, bounce: 0)
    }

    /// The light impact of a state change (the menu button's toggle).
    func playToggleFeedback() {
        feedback.impactOccurred()
    }

    // MARK: Pan

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let anchor else { return }
        let sign: CGFloat = isRightToLeft ? -1 : 1
        switch pan.state {
        case .began:
            feedback.prepare()
            stopSpring()
            wasOpenAtBegin = isOpen
            // The slop is eaten (as UIScrollView does): the card starts moving from where it is, with no jump.
            pan.setTranslation(.zero, in: anchor)
            trackStart = KhalaDrawerMath.rawPosition(position: Double(position), openWidth: Double(openWidth))
        case .changed:
            guard mode == .drawer else { return }
            if pan.numberOfTouches > 1 {
                // A second finger: this is a multi-finger swipe (user gesture settings), not the drawer.
                cancelDrag()
                return
            }
            let travel = Double(pan.translation(in: anchor).x * sign)
            setPosition(CGFloat(KhalaDrawerMath.trackedPosition(
                raw: trackStart + travel,
                openWidth: Double(openWidth)
            )))
        case .ended:
            let velocity = Double(pan.velocity(in: anchor).x * sign)
            let travel = Double(pan.translation(in: anchor).x * sign)
            let ended = mode
            mode = nil
            switch ended {
            case .back:
                if KhalaDrawerMath.goesBack(travel: travel, velocity: velocity) {
                    feedback.impactOccurred()
                    onBack()
                }
            case .drawer:
                let opens = KhalaDrawerMath.opensAfterRelease(
                    position: Double(position),
                    velocity: velocity,
                    openWidth: Double(openWidth)
                )
                if opens != wasOpenAtBegin { feedback.impactOccurred() }
                isOpen = opens
                startSpring(
                    to: opens ? openWidth : 0,
                    velocity: velocity,
                    duration: KhalaDrawerMath.settleDuration,
                    bounce: KhalaDrawerMath.settleBounce(opens: opens, velocity: velocity)
                )
                if opens != wasOpenAtBegin { onCommit(opens) }
            case nil:
                break
            }
        case .cancelled, .failed:
            if mode == .drawer {
                mode = nil
                startSpring(
                    to: isOpen ? openWidth : 0,
                    velocity: 0,
                    duration: KhalaDrawerMath.settleDuration,
                    bounce: 0
                )
            }
            mode = nil
        default:
            break
        }
    }

    private func cancelDrag() {
        pan.isEnabled = false
        pan.isEnabled = true
    }

    // MARK: Blocking

    /// No drawer while a sheet, a cover (still / capture viewer, camera player) or the keyboard is up.
    private var isBlocked: Bool {
        if keyboardIsVisible { return true }
        var controller = host.flatMap(Self.owningController(of:))
        while let current = controller {
            if let presented = current.presentedViewController, !presented.isBeingDismissed { return true }
            controller = current.parent
        }
        return extraPresenters().contains { $0.presentedViewController != nil }
    }

    private static func owningController(of view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }

    @objc private func keyboardWillShow() {
        keyboardIsVisible = true
    }

    @objc private func keyboardWillHide() {
        keyboardIsVisible = false
    }

    // MARK: Spring

    private func currentSpringVelocity() -> Double {
        guard let spring else { return 0 }
        return spring.velocity(at: CACurrentMediaTime() - springStart)
    }

    private func startSpring(to target: CGFloat, velocity: Double, duration: Double, bounce: Double) {
        let spring = KhalaDrawerSpring(
            from: Double(position),
            target: Double(target),
            velocity: velocity,
            duration: duration,
            bounce: bounce
        )
        guard !spring.isSettled(at: 0), openWidth > 0 else {
            stopSpring()
            setPosition(target)
            return
        }
        self.spring = spring
        springStart = CACurrentMediaTime()
        if displayLink == nil {
            let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    private func stopSpring() {
        spring = nil
        displayLink?.invalidate()
        displayLink = nil
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard let spring else {
            stopSpring()
            return
        }
        let time = link.targetTimestamp - springStart
        var value = spring.position(at: time)
        if spring.isSettled(at: time) {
            value = spring.target
            stopSpring()
        } else if value <= 0, spring.target <= 0 {
            // Closing never overshoots: the card lands on the closed edge.
            value = 0
            stopSpring()
        }
        setPosition(CGFloat(max(0, value)))
    }

    private func setPosition(_ value: CGFloat) {
        guard value != position else { return }
        position = value
        onProgress(progress)
    }

    /// CADisplayLink retains its target; the proxy keeps the drawer free (a link outliving it invalidates itself
    /// on its next frame). The link runs on the main run loop.
    @MainActor
    private final class DisplayLinkProxy: NSObject {
        weak var drawer: KhalaDrawer?

        init(_ drawer: KhalaDrawer) {
            self.drawer = drawer
            super.init()
        }

        @objc func tick(_ link: CADisplayLink) {
            guard let drawer else {
                link.invalidate()
                return
            }
            drawer.tick(link)
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension KhalaDrawer: UIGestureRecognizerDelegate {
    /// Which touches the drawer even looks at. Closed: anywhere on a native screen except on a control that drags
    /// sideways (`claimsHorizontalDrag`); only the leading-edge zone over the web UI. Open or moving: anywhere. A
    /// touch it ignores costs nothing: nothing waits for it.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === pan, let anchor else { return false }
        // A second finger joins the same gesture (it is counted, then refused as multi-touch).
        if pan.numberOfTouches > 0 { return true }
        guard !isBlocked, openWidth > 0 else { return false }
        let point = touch.location(in: anchor)
        guard anchor.bounds.contains(point) else { return false }
        touchStart = point
        if isOpen || isSettling || position > 0 { return true }
        if context().isWebScreen {
            return KhalaDrawerMath.isInEdgeZone(
                x: Double(point.x),
                width: Double(anchor.bounds.width),
                rightToLeft: isRightToLeft
            )
        }
        return !Self.claimsHorizontalDrag(
            from: touch.view,
            below: host,
            windowPoint: touch.location(in: nil),
            window: anchor.window,
            rightToLeft: isRightToLeft
        )
    }

    /// The one decision, at the slop: horizontal enough, the right way, one finger.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan, let anchor else { return true }
        guard pan.numberOfTouches <= 1, !isBlocked else { return false }
        let sign: CGFloat = isRightToLeft ? -1 : 1
        var vector = pan.translation(in: anchor)
        if vector == .zero { vector = pan.velocity(in: anchor) }
        let allowed = KhalaDrawerMath.allowedDirection(
            position: Double(position),
            openWidth: Double(openWidth),
            isSettling: isSettling
        )
        let inEdgeZone = allowed == .open && KhalaDrawerMath.isInEdgeZone(
            x: Double(touchStart.x),
            width: Double(anchor.bounds.width),
            rightToLeft: isRightToLeft
        )
        guard KhalaDrawerMath.claims(
            dx: Double(vector.x * sign),
            dy: Double(vector.y),
            allowed: allowed,
            inEdgeZone: inEdgeZone
        ) else { return false }
        let context = context()
        mode = allowed == .open && context.isWebScreen && context.showsBack ? .back : .drawer
        return true
    }

    /// Scroll views' pans (the web view's, the menu's, a screen's) and screen-edge pans (upstream's stand-by
    /// overlay) wait for the drawer's decision at the slop. Never the reverse: a drawer waiting on a scroll view
    /// would lose every horizontal drag the scroll view claims.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === pan, let host, let otherView = otherGestureRecognizer.view,
              otherView.isDescendant(of: host) else { return false }
        if otherGestureRecognizer is UIScreenEdgePanGestureRecognizer { return true }
        if let scrollView = otherView as? UIScrollView, scrollView.panGestureRecognizer === otherGestureRecognizer {
            return true
        }
        return false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    /// Whether the touched view, or one of its ancestors up to the shell's host, drags sideways itself: a slider,
    /// a switch, a tab bar (iOS 26's scrubbing lens), a segmented control, a horizontal scroller that isn't at its
    /// leading boundary (it would scroll back first), or a SwiftUI control marked with
    /// `khalaClaimsHorizontalDrags()` (SwiftUI controls have no UIView of their own in the hit-test chain).
    static func claimsHorizontalDrag(
        from view: UIView?,
        below host: UIView?,
        windowPoint: CGPoint,
        window: UIWindow?,
        rightToLeft: Bool
    ) -> Bool {
        var current = view
        while let candidate = current, candidate !== host {
            switch candidate {
            case is UISlider, is UISwitch, is UITabBar, is UISegmentedControl:
                return true
            case let scrollView as UIScrollView:
                if scrollView.isScrollEnabled, Self.scrollsTowardLeading(scrollView, rightToLeft: rightToLeft) {
                    return true
                }
            default:
                break
            }
            current = candidate.superview
        }
        return KhalaDrawerExclusion.contains(windowPoint: windowPoint, in: window)
    }

    /// A horizontal scroller with room to scroll back toward its leading edge.
    private static func scrollsTowardLeading(_ scrollView: UIScrollView, rightToLeft: Bool) -> Bool {
        let inset = scrollView.adjustedContentInset
        let minimum = -inset.left
        let maximum = scrollView.contentSize.width + inset.right - scrollView.bounds.width
        guard maximum > minimum + 1 else { return false }
        let offset = scrollView.contentOffset.x
        return rightToLeft ? offset < maximum - 1 : offset > minimum + 1
    }
}
