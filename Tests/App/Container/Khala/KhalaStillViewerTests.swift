import Foundation
@testable import HomeAssistant
import Testing

/// The zoomable still viewer (captures and snapshots): the still fitted inside the screen and kept centred while
/// zoomed, and the pager's rules — a page turn only at 1×, only for a sideways drag, the pages kept and loaded around
/// the one on screen.
struct KhalaStillZoomTests {
    @Test func aStillIsFittedInsideTheScreen() {
        let portrait = CGSize(width: 390, height: 844)
        // A 16:9 camera frame on a portrait phone: full width, letterboxed above and below.
        #expect(KhalaLiveZoom.fittedSize(CGSize(width: 2688, height: 1512), in: portrait)
            == CGSize(width: 390, height: 219.375))
        // A tall image on a landscape screen: full height, pillarboxed.
        #expect(KhalaLiveZoom.fittedSize(CGSize(width: 1000, height: 2000), in: CGSize(width: 844, height: 390))
            == CGSize(width: 195, height: 390))
        // No image yet (or an empty one): the content fills the screen, as the live player's does.
        #expect(KhalaLiveZoom.fittedSize(.zero, in: portrait) == portrait)
        #expect(KhalaLiveZoom.fittedSize(CGSize(width: 16, height: 9), in: .zero) == .zero)
    }

    @Test func aZoomedStillStaysCentredUntilItFillsAnAxis() {
        let screen = CGSize(width: 390, height: 844)
        #expect(KhalaLiveZoom.centringInset(content: CGSize(width: 390, height: 219.375), in: screen)
            == CGSize(width: 0, height: 312.3125))
        // At 4× the frame is taller than the screen: no inset left, it pans edge to edge.
        #expect(KhalaLiveZoom.centringInset(content: CGSize(width: 1560, height: 877.5), in: screen) == .zero)
        // The live player's content always fills its bounds, so it never gets an inset.
        #expect(KhalaLiveZoom.centringInset(content: screen, in: screen) == .zero)
    }

    @Test func doubleTapOnAStillZoomsInsideTheFittedImage() {
        // The zoom rectangle is in the fitted image's own coordinates, so a tap near its edge stays on the image.
        let fitted = CGSize(width: 390, height: 219.375)
        #expect(KhalaLiveZoom.zoomRect(scale: 2.5, center: CGPoint(x: 390, y: 0), in: fitted)
            == CGRect(x: 234, y: 0, width: 156, height: 87.75))
    }
}

struct KhalaStillPagingTests {
    @Test func pagesSitAGapApart() {
        #expect(KhalaStillPaging.stride(width: 390) == 410)
        #expect(KhalaStillPaging.pageX(0, width: 390) == 10)
        #expect(KhalaStillPaging.pageX(3, width: 390) == 1240)
    }

    @Test func thePageOnScreenIsTheNearestOne() {
        #expect(KhalaStillPaging.index(offset: 0, width: 390, count: 5) == 0)
        #expect(KhalaStillPaging.index(offset: 204, width: 390, count: 5) == 0)
        #expect(KhalaStillPaging.index(offset: 206, width: 390, count: 5) == 1)
        #expect(KhalaStillPaging.index(offset: 820, width: 390, count: 5) == 2)
        // Rubber-banding past either end still names an end page.
        #expect(KhalaStillPaging.index(offset: -120, width: 390, count: 5) == 0)
        #expect(KhalaStillPaging.index(offset: 9000, width: 390, count: 5) == 4)
        #expect(KhalaStillPaging.index(offset: 300, width: 390, count: 0) == 0)
        #expect(KhalaStillPaging.index(offset: 300, width: 0, count: 3) == 0)
    }

    @Test func onlyTheNeighbourhoodIsKeptAndLoaded() {
        #expect(KhalaStillPaging.window(around: 0, count: 1) == 0 ... 0)
        #expect(KhalaStillPaging.window(around: 0, count: 5) == 0 ... 1)
        #expect(KhalaStillPaging.window(around: 2, count: 5) == 1 ... 3)
        #expect(KhalaStillPaging.window(around: 4, count: 5) == 3 ... 4)
        #expect(KhalaStillPaging.window(around: 9, count: 5) == 3 ... 4)
        #expect(KhalaStillPaging.window(around: 0, count: 0) == nil)

        #expect(KhalaStillPaging.loadOrder(around: 2, count: 5) == [2, 3, 1])
        #expect(KhalaStillPaging.loadOrder(around: 0, count: 5) == [0, 1])
        #expect(KhalaStillPaging.loadOrder(around: 4, count: 5) == [4, 3])
        #expect(KhalaStillPaging.loadOrder(around: 0, count: 1) == [0])

        #expect(KhalaStillPaging.keeps(4, around: 2))
        #expect(KhalaStillPaging.keeps(0, around: 2))
        #expect(!KhalaStillPaging.keeps(5, around: 2))
    }

    @Test func aPageTurnsOnlyAtOneTimes() {
        #expect(KhalaStillPaging.allowsPaging(zoomScale: 1))
        // Mid-bounce below 1× and the sub-threshold wobble of a pinch's end are still unzoomed.
        #expect(KhalaStillPaging.allowsPaging(zoomScale: 0.9))
        #expect(KhalaStillPaging.allowsPaging(zoomScale: 1.01))
        #expect(!KhalaStillPaging.allowsPaging(zoomScale: 1.02))
        #expect(!KhalaStillPaging.allowsPaging(zoomScale: 2.5))
        #expect(!KhalaStillPaging.allowsPaging(zoomScale: 4))
    }

    @Test func onlyASidewaysDragTurnsThePage() {
        #expect(KhalaStillPaging.beginsPaging(velocity: CGPoint(x: -600, y: 80), translation: .zero))
        #expect(KhalaStillPaging.beginsPaging(velocity: CGPoint(x: 300, y: -200), translation: .zero))
        // Downward: the swipe that closes the viewer.
        #expect(!KhalaStillPaging.beginsPaging(velocity: CGPoint(x: 100, y: 700), translation: .zero))
        #expect(!KhalaStillPaging.beginsPaging(velocity: CGPoint(x: 200, y: 200), translation: .zero))
        // A slow drag with no velocity yet is read from how far it moved.
        #expect(KhalaStillPaging.beginsPaging(velocity: .zero, translation: CGPoint(x: 12, y: 3)))
        #expect(!KhalaStillPaging.beginsPaging(velocity: .zero, translation: CGPoint(x: 2, y: 11)))
    }
}
