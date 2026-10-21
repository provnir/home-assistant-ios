import Foundation

/// Where a timeline row sits relative to Now.
enum KhalaTimelinePhase: Equatable {
    case upcoming
    case now
    case past
}

/// The stretch of the vertical line above or below a row's dot: ink through the past, the light line through
/// what's coming, nothing past either end.
enum KhalaTimelineStroke: Equatable {
    case none
    case upcoming
    case past
}

/// Every timeline and time-ordered list shows its NEWEST AT THE TOP (Nir, build 24.1): time increases upward.
/// Top to bottom: furthest future … nearest future, Now, most recent past … oldest past. The screens open on Now
/// (`KhalaNowScrollView`), so what's coming sits above it, reachable by scrolling up, and the past runs on below.
///
/// Pure ordering for the screens' own item types; Today's `KhalaTimeline` uses the same phases and strokes.
struct KhalaTimelineOrder<Item: Identifiable> {
    enum RowID: Hashable {
        case now
        case item(Item.ID)
    }

    struct Row: Identifiable {
        /// Nil for the Now row.
        let item: Item?
        let phase: KhalaTimelinePhase
        let strokeAbove: KhalaTimelineStroke
        let strokeBelow: KhalaTimelineStroke

        var id: RowID { item.map { .item($0.id) } ?? .now }
    }

    /// Top to bottom.
    let rows: [Row]

    /// - Parameters:
    ///   - upcoming: what's coming, in any order (ties keep their given order, nearest lowest).
    ///   - past: what happened, in any order (ties keep their given order, the first given highest).
    ///   - date: an item's time.
    ///   - showsNow: whether a Now row sits between the two.
    init(upcoming: [Item], past: [Item], date: (Item) -> Date, showsNow: Bool) {
        let future = Self.latestFirst(upcoming, date: date, tiesReversed: true)
        let history = Self.latestFirst(past, date: date, tiesReversed: false)
        var entries: [(Item?, KhalaTimelinePhase)] = future.map { ($0, .upcoming) }
        if showsNow { entries.append((nil, .now)) }
        entries += history.map { ($0, .past) }
        let strokes = KhalaTimelineLine.strokes(entries.map(\.1))
        rows = zip(entries, strokes).map { entry, stroke in
            Row(item: entry.0, phase: entry.1, strokeAbove: stroke.above, strokeBelow: stroke.below)
        }
    }

    /// The Now row's position, nil when there is none.
    var nowIndex: Int? { rows.firstIndex { $0.phase == .now } }

    /// The ids of the rows above Now, top to bottom: when they change, Now moves on screen.
    var idsAboveNow: [RowID] { rows.prefix(nowIndex ?? 0).map(\.id) }

    /// Latest first; equal dates keep their given order (or its reverse, for a list given nearest-first that
    /// should read nearest-lowest).
    private static func latestFirst(_ items: [Item], date: (Item) -> Date, tiesReversed: Bool) -> [Item] {
        items.enumerated()
            .sorted { lhs, rhs in
                let left = date(lhs.element), right = date(rhs.element)
                if left != right { return left > right }
                return tiesReversed ? lhs.offset > rhs.offset : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

/// The line's strokes for a column of rows, top to bottom.
enum KhalaTimelineLine {
    struct Strokes: Equatable {
        let above: KhalaTimelineStroke
        let below: KhalaTimelineStroke
    }

    /// The stretch between two neighbouring rows belongs to the lower one's time: ink when the lower row is in the
    /// past (so it runs solid from the newest past up into Now), the light line when it is Now or upcoming. Nothing
    /// above the top row or below the bottom one.
    static func strokes(_ phases: [KhalaTimelinePhase]) -> [Strokes] {
        phases.indices.map { index in
            let above: KhalaTimelineStroke = index == 0 ? .none : stroke(into: phases[index])
            let below: KhalaTimelineStroke = index == phases.count - 1 ? .none : stroke(into: phases[index + 1])
            return Strokes(above: above, below: below)
        }
    }

    private static func stroke(into lower: KhalaTimelinePhase) -> KhalaTimelineStroke {
        lower == .past ? .past : .upcoming
    }

    /// A list sorted on optional dates, latest first, the undated ones (no next run) last in their given order.
    static func latestFirst<Item>(_ items: [Item], date: (Item) -> Date?) -> [Item] {
        items.enumerated()
            .sorted { lhs, rhs in
                switch (date(lhs.element), date(rhs.element)) {
                case let (left?, right?) where left != right: return left > right
                case (.some, nil): return true
                case (nil, .some): return false
                default: return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }
}
