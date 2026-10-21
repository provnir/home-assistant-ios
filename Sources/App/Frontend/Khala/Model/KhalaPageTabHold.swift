import Foundation

/// Keeps a tabbed Home Assistant page's chrome on screen while one of its tabs loads.
///
/// Choosing a tab makes the frontend swap pages: the script reports the old page, then *no* page (the new one
/// isn't laid out yet), then the new page. Without a hold, that empty report tears Khala's page header down and
/// builds it again, so the glass tab bar is a new view and its lens jumps to the new tab instead of moving there
/// (build 19.1: "bottom tabs lack the transition animation"), and the header flickers. The hold answers the gap
/// with the header as it was, the chosen tab already active, for at most `duration`.
struct KhalaPageTabHold: Equatable {
    /// Long enough for the frontend to lay out the next tab's page; short enough that a page which never
    /// reports doesn't keep stale chrome up.
    static let duration: TimeInterval = 2

    let header: KhalaPageHeader
    let until: Date

    /// Nil when there is no page chrome to hold.
    init?(header: KhalaPageHeader?, selecting path: String, now: Date, duration: TimeInterval = Self.duration) {
        guard let header, header.tabs.contains(where: { $0.path == path }) else { return nil }
        self.header = header.selectingTab(path: path)
        self.until = now.addingTimeInterval(duration)
    }

    /// The header to draw: the frontend's own report when there is one, else the held one while it lasts.
    func header(fresh: KhalaPageHeader?, now: Date) -> KhalaPageHeader? {
        if let fresh { return fresh }
        return now < until ? header : nil
    }
}
