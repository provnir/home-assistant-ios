import Foundation

/// The still viewer's paging rules (`KhalaStillPager`): a horizontal, paging `UIScrollView` of zoom containers, one
/// per capture, with a gap between pages as in Photos. A page turns only at 1×: while the page on screen is zoomed the
/// pager's own scrolling is off, so neither a pan nor its momentum at the image's edge can flip it, and a drag only
/// starts a page turn when it is mostly sideways (a downward one is the swipe that closes the viewer).
/// All values in points, in the pager's scroll view's coordinates.
enum KhalaStillPaging {
    /// The black gap between two pages while one slides over the other.
    static let gap: CGFloat = 20

    /// How far apart two pages are: a page's width and the gap.
    static func stride(width: CGFloat) -> CGFloat {
        width + gap
    }

    /// Where page `index` starts: the scroll view is a gap wider than the screen, half of it on each side.
    static func pageX(_ index: Int, width: CGFloat) -> CGFloat {
        CGFloat(index) * stride(width: width) + gap / 2
    }

    /// The page mostly on screen at horizontal `offset`.
    static func index(offset: CGFloat, width: CGFloat, count: Int) -> Int {
        guard count > 0, width > 0 else { return 0 }
        let page = Int((offset / stride(width: width)).rounded())
        return min(max(page, 0), count - 1)
    }

    /// The pages kept as views: the one on screen and its neighbours, so a page turn never shows an empty one.
    static func window(around index: Int, count: Int) -> ClosedRange<Int>? {
        guard count > 0 else { return nil }
        let index = min(max(index, 0), count - 1)
        return max(index - 1, 0) ... min(index + 1, count - 1)
    }

    /// The order full-size images load in: the page on screen, then the one a swipe is most likely to bring (the
    /// next, newer capture), then the previous one.
    static func loadOrder(around index: Int, count: Int) -> [Int] {
        [index, index + 1, index - 1].filter { (0 ..< count).contains($0) }
    }

    /// The full-size images worth keeping in memory (each a decoded camera frame of several megabytes): two pages
    /// either side of the one on screen.
    static func keeps(_ page: Int, around index: Int) -> Bool {
        abs(page - index) <= 2
    }

    /// Paging works only at 1×.
    static func allowsPaging(zoomScale: CGFloat) -> Bool {
        !KhalaLiveZoom.isZoomed(zoomScale)
    }

    /// Whether a drag may start a page turn: mostly sideways. Read from its velocity as it begins, or from how far it
    /// has moved when that is still zero.
    static func beginsPaging(velocity: CGPoint, translation: CGPoint) -> Bool {
        let motion = velocity == .zero ? translation : velocity
        return abs(motion.x) > abs(motion.y)
    }
}
