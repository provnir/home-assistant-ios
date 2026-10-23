import UIKit

/// Pinch and double-tap zoom with pan, momentum and edge rubber-banding around any view, a tap for the chrome, an
/// optional long press and swipe down to close. One container for both zooming hosts: the live player puts its
/// WKWebView in it (`KhalaLiveZoomView`), the still viewer an image view per page (`KhalaStillPager`).
///
/// The zoom is a `UIScrollView` whose zooming view holds the hosted view:
/// - the scroll view scales the hosted view's layer tree on the render server, so every frame of a pinch, a pan,
///   the deceleration and the bounce back past 1× or 4× runs at the display's rate with no JavaScript or IPC in the
///   loop (for live, a CSS transform would need an `evaluateJavaScript` per gesture update);
/// - a scaled layer is sampled from its source — the decoded video frame (2688×1520 here), the full-size image — so
///   zooming in shows the picture's own detail, not an upscaled screen-size bitmap;
/// - momentum, rubber-banding and `zoom(to:animated:)` are UIKit's own, the same physics as Photos.
///
/// Unzoomed, the scroll view's pan is off: a one-finger drag belongs to whatever is around the container (the
/// screen's scroll, the still pager's page turn, swipe down).
final class KhalaZoomContainer: UIView, UIScrollViewDelegate {
    var allowsSwipeDown = false
    /// Off while something else owns the fingers (the still pager mid page turn): no pinch, no double tap.
    var allowsZoom = true {
        didSet {
            scrollView.pinchGestureRecognizer?.isEnabled = allowsZoom
            doubleTap.isEnabled = allowsZoom
        }
    }

    /// The hosted content's own size (a still's pixel size). Set, the content is that shape fitted inside the
    /// container and kept centred while it is smaller than it, so a zoomed still pans to its own edges, not into
    /// the letterbox. `nil` (the live player: the page letterboxes its video itself) fills the container.
    var contentAspect: CGSize? {
        didSet {
            guard contentAspect != oldValue else { return }
            laidOutSize = .zero
            setNeedsLayout()
        }
    }

    var onTap: (() -> Void)?
    /// `nil`: no long press (no haptic either).
    var onLongPress: (() -> Void)?
    /// The scale, throttled to what the zoom chip can show.
    var onZoom: ((CGFloat) -> Void)?
    /// Exactly when the content goes from unzoomed to zoomed and back (the still pager's paging gate).
    var onZoomedChange: ((Bool) -> Void)?
    var onDismissProgress: ((CGFloat) -> Void)?
    var onDismiss: (() -> Void)?

    var zoomScale: CGFloat { scrollView.zoomScale }
    var isZoomed: Bool { KhalaLiveZoom.isZoomed(scrollView.zoomScale) }

    private let scrollView = UIScrollView()
    private let content = UIView()
    private weak var hosted: UIView?
    private var laidOutSize: CGSize = .zero
    private var reportedScale: CGFloat = 1
    private var reportedZoomed = false
    private let doubleTap = UITapGestureRecognizer()
    private let dismissGate = KhalaGestureGate()
    private lazy var dismissPan: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = dismissGate
        return pan
    }()

    init(hosting view: UIView) {
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = true

        scrollView.delegate = self
        scrollView.minimumZoomScale = KhalaLiveZoom.minimum
        scrollView.maximumZoomScale = KhalaLiveZoom.maximum
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.scrollsToTop = false
        scrollView.decelerationRate = .normal
        scrollView.backgroundColor = .clear
        scrollView.panGestureRecognizer.isEnabled = false
        addSubview(scrollView)
        content.backgroundColor = .clear
        scrollView.addSubview(content)

        hosted = view
        view.removeFromSuperview()
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.addSubview(view)

        doubleTap.addTarget(self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        addGestureRecognizer(longPress)
        dismissGate.shouldBegin = { [weak self] recognizer in
            self?.shouldBeginDismiss(recognizer as? UIPanGestureRecognizer) ?? false
        }
        addGestureRecognizer(dismissPan)

        accessibilityTraits = .image
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        // A new size (rotation, the card resizing, a still arriving) starts unzoomed: the old zoom rectangle means
        // nothing in it.
        scrollView.zoomScale = KhalaLiveZoom.minimum
        scrollView.frame = bounds
        let size = contentAspect.map { KhalaLiveZoom.fittedSize($0, in: bounds.size) } ?? bounds.size
        content.frame = CGRect(origin: .zero, size: size)
        hosted?.frame = content.bounds
        scrollView.contentSize = size
        centreContent()
        scrollView.contentOffset = CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
        zoomChanged()
    }

    func resetZoom(animated: Bool) {
        scrollView.setZoomScale(KhalaLiveZoom.minimum, animated: animated)
    }

    /// Lets the hosted view go (only if it is still ours): the live player's web view is its session's.
    func detachHosted() {
        if let hosted, hosted.superview === content {
            hosted.removeFromSuperview()
        }
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        content
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centreContent()
        zoomChanged()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        zoomChanged()
    }

    /// A fitted still smaller than the container along an axis sits in its middle. Content that fills the
    /// container (live's) is left exactly as the live player has always laid it out: no inset, ever.
    private func centreContent() {
        guard contentAspect != nil else { return }
        let inset = KhalaLiveZoom.centringInset(content: scrollView.contentSize, in: bounds.size)
        scrollView.contentInset = UIEdgeInsets(
            top: inset.height, left: inset.width, bottom: inset.height, right: inset.width
        )
    }

    private func zoomChanged() {
        let scale = scrollView.zoomScale
        let zoomed = KhalaLiveZoom.isZoomed(scale)
        scrollView.panGestureRecognizer.isEnabled = zoomed
        if zoomed != reportedZoomed {
            reportedZoomed = zoomed
            onZoomedChange?(zoomed)
        }
        // The chip shows tenths; spare SwiftUI a re-render for every sub-pixel step of a pinch.
        guard abs(scale - reportedScale) >= 0.05 || (scale == KhalaLiveZoom.minimum && reportedScale != scale) else {
            return
        }
        reportedScale = scale
        onZoom?(scale)
    }

    // MARK: Gestures

    @objc private func handleTap() {
        onTap?()
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        let next = KhalaLiveZoom.nextStep(after: scrollView.zoomScale)
        guard next > KhalaLiveZoom.minimum else {
            resetZoom(animated: true)
            return
        }
        let point = recognizer.location(in: content)
        scrollView.zoom(to: KhalaLiveZoom.zoomRect(scale: next, center: point, in: content.bounds.size), animated: true)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let onLongPress else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onLongPress()
    }

    /// Full screen, unzoomed: the picture follows the finger down and either closes or springs back.
    @objc private func handleDismissPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = max(recognizer.translation(in: self).y, 0)
        switch recognizer.state {
        case .changed:
            let progress = KhalaLiveZoom.dismissProgress(translation: translation, height: bounds.height)
            scrollView.transform = CGAffineTransform(translationX: 0, y: translation)
                .scaledBy(x: 1 - progress * 0.15, y: 1 - progress * 0.15)
            onDismissProgress?(progress)
        case .ended:
            if KhalaLiveZoom.shouldDismiss(translation: translation, velocity: recognizer.velocity(in: self).y) {
                onDismiss?()
            } else {
                springBack()
            }
        case .cancelled, .failed:
            springBack()
        default:
            break
        }
    }

    private func springBack() {
        UIView.animate(
            withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.scrollView.transform = .identity
        }
        onDismissProgress?(0)
    }

    /// Only full screen, only unzoomed, only a drag that starts downwards.
    private func shouldBeginDismiss(_ pan: UIPanGestureRecognizer?) -> Bool {
        guard let pan, allowsSwipeDown, !isZoomed else { return false }
        let velocity = pan.velocity(in: self)
        return velocity.y > 0 && velocity.y > abs(velocity.x)
    }
}
