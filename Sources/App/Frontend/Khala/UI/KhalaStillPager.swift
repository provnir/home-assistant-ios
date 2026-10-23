import UIKit

/// The still viewer's pages: a horizontal, paging `UIScrollView` of zoom containers (`KhalaZoomContainer`, the live
/// player's own), each an image view at its still's full size. UIKit rather than SwiftUI's paged `TabView`, because
/// the page turn has to answer to the zoom inside it, which a `TabView` gives no handle on:
/// - a page turns only at 1× (`KhalaStillPaging.allowsPaging`): while the page on screen is zoomed the pager's
///   scrolling is off, so a pan — or its momentum running into the image's edge, which a nested scroll view would
///   otherwise hand on to the pager — never flips the page;
/// - a drag starts a page turn only when it is mostly sideways (`KhalaStillPaging.beginsPaging`); a downward one is
///   the page's swipe to close;
/// - no pinch or double tap while a page turn is under way, and a page leaving the screen goes back to 1×;
/// - only the page on screen and its neighbours exist as views (a day can hold a hundred captures).
final class KhalaStillPager: UIView, UIScrollViewDelegate {
    var onIndex: ((Int) -> Void)?
    var onTap: (() -> Void)?
    /// The page on screen's zoom (for the chip).
    var onZoom: ((CGFloat) -> Void)?
    var onDismissProgress: ((CGFloat) -> Void)?
    var onDismiss: (() -> Void)?

    private(set) var index = 0
    private var stills: [KhalaStill] = []
    private let scroller = PagingScrollView()
    private var pages: [Int: Page] = [:]
    private var laidOutSize: CGSize = .zero
    /// Frames and offsets being set by the pager itself: not a page turn.
    private var isLayingOut = false
    /// A finger, or the momentum it left, is turning the page.
    private var isTurning = false

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = true

        scroller.delegate = self
        scroller.isPagingEnabled = true
        scroller.bounces = true
        scroller.alwaysBounceVertical = false
        scroller.alwaysBounceHorizontal = false
        scroller.showsVerticalScrollIndicator = false
        scroller.showsHorizontalScrollIndicator = false
        scroller.contentInsetAdjustmentBehavior = .never
        scroller.scrollsToTop = false
        scroller.backgroundColor = .clear
        // Two fingers are a pinch on the page, never a page turn.
        scroller.panGestureRecognizer.maximumNumberOfTouches = 1
        addSubview(scroller)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The pages and the one to show. A new list (the day's captures arriving around the one opened) rebuilds the
    /// pages and moves to `index` at once; otherwise `index` only moves the pager when no page turn is under way, so
    /// a late echo of a turn never pulls it back.
    func show(_ stills: [KhalaStill], at index: Int) {
        let isNewList = stills.map(\.id) != self.stills.map(\.id)
        self.stills = stills
        let target = min(max(index, 0), max(stills.count - 1, 0))
        if isNewList {
            pages.values.forEach { $0.container.removeFromSuperview() }
            pages = [:]
        }
        if isNewList || (target != self.index && !isTurning) {
            pages[self.index]?.container.resetZoom(animated: false)
            self.index = target
            layoutPages()
            // Called from SwiftUI's update of the pager: the chip hears of the new page's 1× after it.
            DispatchQueue.main.async { [weak self] in self?.onZoom?(KhalaLiveZoom.minimum) }
        }
        tile()
        updatePagingGate()
    }

    /// The zoom chip: the page on screen back to 1×.
    func resetZoom() {
        pages[index]?.container.resetZoom(animated: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize else { return }
        // A rotation keeps the page; each page's container starts it again at 1× in its new size.
        laidOutSize = bounds.size
        layoutPages()
    }

    // MARK: UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isLayingOut, bounds.width > 0 else { return }
        let newIndex = KhalaStillPaging.index(
            offset: scrollView.contentOffset.x, width: bounds.width, count: stills.count
        )
        guard newIndex != index else { return }
        pages[index]?.container.resetZoom(animated: false)
        index = newIndex
        tile()
        updatePagingGate()
        onZoom?(pages[index]?.container.zoomScale ?? KhalaLiveZoom.minimum)
        onIndex?(newIndex)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        setTurning(true)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { setTurning(false) }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        setTurning(false)
    }

    // MARK: Accessibility

    /// VoiceOver's three-finger swipe turns the page (at 1× only, as a finger does).
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let target: Int
        switch direction {
        case .left, .next: target = index + 1
        case .right, .previous: target = index - 1
        default: return false
        }
        guard stills.indices.contains(target),
              KhalaStillPaging.allowsPaging(zoomScale: pages[index]?.container.zoomScale ?? 1) else { return false }
        scroller.setContentOffset(CGPoint(x: CGFloat(target) * KhalaStillPaging.stride(width: bounds.width), y: 0),
                                  animated: false)
        UIAccessibility.post(notification: .pageScrolled, argument: stills[target].accessibilityLabel)
        return true
    }

    // MARK: Pages

    private func layoutPages() {
        let width = bounds.width
        guard width > 0 else { return }
        isLayingOut = true
        let stride = KhalaStillPaging.stride(width: width)
        // A gap wider than the screen, half of it either side, so pages slide apart with black between them.
        scroller.frame = CGRect(x: -KhalaStillPaging.gap / 2, y: 0, width: stride, height: bounds.height)
        scroller.contentSize = CGSize(width: stride * CGFloat(stills.count), height: bounds.height)
        scroller.contentOffset = CGPoint(x: CGFloat(index) * stride, y: 0)
        for (page, view) in pages {
            view.container.frame = pageFrame(page)
        }
        isLayingOut = false
    }

    private func pageFrame(_ page: Int) -> CGRect {
        CGRect(x: KhalaStillPaging.pageX(page, width: bounds.width), y: 0, width: bounds.width, height: bounds.height)
    }

    /// Keeps the page on screen and its neighbours as views, each showing its still as it is now.
    private func tile() {
        guard let kept = KhalaStillPaging.window(around: index, count: stills.count) else {
            pages.values.forEach { $0.container.removeFromSuperview() }
            pages = [:]
            return
        }
        for (page, view) in pages where !kept.contains(page) {
            view.container.removeFromSuperview()
            pages[page] = nil
        }
        for page in kept {
            let view = pages[page] ?? makePage(page)
            view.show(stills[page])
        }
    }

    private func makePage(_ page: Int) -> Page {
        let view = Page()
        let container = view.container
        container.frame = pageFrame(page)
        container.allowsSwipeDown = true
        container.allowsZoom = !isTurning
        // Its scroll view clips the picture; the container itself must not, or a swipe down would cut the picture
        // off at the page's bottom edge as it follows the finger.
        container.clipsToBounds = false
        container.onTap = { [weak self] in self?.onTap?() }
        container.onZoom = { [weak self, weak container] scale in
            guard let self, let container, self.pages[self.index]?.container === container else { return }
            self.onZoom?(scale)
        }
        container.onZoomedChange = { [weak self] _ in self?.updatePagingGate() }
        container.onDismissProgress = { [weak self] in self?.onDismissProgress?($0) }
        container.onDismiss = { [weak self] in self?.onDismiss?() }
        scroller.addSubview(container)
        pages[page] = view
        return view
    }

    private func updatePagingGate() {
        scroller.isScrollEnabled = KhalaStillPaging.allowsPaging(
            zoomScale: pages[index]?.container.zoomScale ?? KhalaLiveZoom.minimum
        )
    }

    private func setTurning(_ turning: Bool) {
        isTurning = turning
        pages.values.forEach { $0.container.allowsZoom = !turning }
    }

    /// One page: the zoom container around an image view, and a spinner while the full-size image loads.
    private final class Page {
        let imageView: UIImageView
        let spinner = UIActivityIndicatorView(style: .large)
        let container: KhalaZoomContainer

        init() {
            let imageView = UIImageView()
            // The container fits its content to the image's shape; aspect fit only guards a stale frame.
            imageView.contentMode = .scaleAspectFit
            self.imageView = imageView
            container = KhalaZoomContainer(hosting: imageView)
            container.isAccessibilityElement = true
            spinner.color = .white
            spinner.hidesWhenStopped = true
            spinner.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin,
                                        .flexibleBottomMargin]
            container.addSubview(spinner)
        }

        func show(_ still: KhalaStill) {
            if imageView.image !== still.image {
                imageView.image = still.image
                // A new shape lays the page out again, at 1×.
                container.contentAspect = still.image?.size
            }
            if still.image == nil {
                spinner.center = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
                spinner.startAnimating()
            } else {
                spinner.stopAnimating()
            }
            container.accessibilityLabel = still.accessibilityLabel
        }
    }

    /// A drag that starts mostly up or down is not a page turn (it is the page's swipe to close, or nothing).
    private final class PagingScrollView: UIScrollView {
        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === panGestureRecognizer,
               !KhalaStillPaging.beginsPaging(
                   velocity: panGestureRecognizer.velocity(in: self),
                   translation: panGestureRecognizer.translation(in: self)
               ) {
                return false
            }
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
    }
}
