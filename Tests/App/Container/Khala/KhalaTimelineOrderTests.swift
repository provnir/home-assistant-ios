import Foundation
@testable import HomeAssistant
import Testing

/// Newest on top (Nir, build 24.1): furthest future … nearest, Now, latest past … earliest. Synthetic fixtures only.
struct KhalaTimelineOrderTests {
    private struct Event: Identifiable, Equatable {
        let id: String
        let date: Date
    }

    private static let base = Date(timeIntervalSince1970: 1_800_000_000)
    private static func event(_ id: String, _ minutes: Double) -> Event {
        Event(id: id, date: base.addingTimeInterval(minutes * 60))
    }

    @Test func futureAboveNowAndPastBelowItLatestFirst() {
        let order = KhalaTimelineOrder(
            upcoming: [Self.event("soon", 10), Self.event("tonight", 300), Self.event("later", 60)],
            past: [Self.event("morning", -300), Self.event("justNow", -5), Self.event("noon", -60)],
            date: \.date,
            showsNow: true
        )
        #expect(order.rows.map { $0.item?.id ?? "NOW" } == ["tonight", "later", "soon", "NOW", "justNow", "noon", "morning"])
        #expect(order.rows.map(\.phase) == [.upcoming, .upcoming, .upcoming, .now, .past, .past, .past])
        #expect(order.nowIndex == 3)
        #expect(order.idsAboveNow == [.item("tonight"), .item("later"), .item("soon")])
    }

    @Test func pastSolidBelowNowUpcomingLightAboveIt() {
        let order = KhalaTimelineOrder(
            upcoming: [Self.event("a", 10), Self.event("b", 20)],
            past: [Self.event("c", -10), Self.event("d", -20)],
            date: \.date,
            showsNow: true
        )
        #expect(order.rows.map(\.strokeAbove) == [.none, .upcoming, .upcoming, .past, .past])
        #expect(order.rows.map(\.strokeBelow) == [.upcoming, .upcoming, .past, .past, .none])
    }

    @Test func noFutureStartsAtNowAndNoNowRowWhenNotAsked() {
        let onlyPast = KhalaTimelineOrder(
            upcoming: [],
            past: [Self.event("old", -90), Self.event("new", -10)],
            date: \.date,
            showsNow: true
        )
        #expect(onlyPast.nowIndex == 0)
        #expect(onlyPast.idsAboveNow.isEmpty)

        let recent = KhalaTimelineOrder(
            upcoming: [],
            past: [Self.event("old", -90), Self.event("new", -10)],
            date: \.date,
            showsNow: false
        )
        #expect(recent.nowIndex == nil)
        #expect(recent.rows.map { $0.item?.id } == ["new", "old"])
        #expect(recent.rows.map(\.strokeAbove) == [.none, .past])
        #expect(recent.rows.map(\.strokeBelow) == [.past, .none])
    }

    @Test func tiesReadAsTheReverseOfTimeOrder() {
        // Upcoming given nearest-first: at the same minute the first given sits lowest (nearest Now).
        let order = KhalaTimelineOrder(
            upcoming: [Self.event("first", 10), Self.event("second", 10)],
            past: [Self.event("newer", -10), Self.event("older", -10)],
            date: \.date,
            showsNow: true
        )
        #expect(order.rows.map { $0.item?.id ?? "NOW" } == ["second", "first", "NOW", "newer", "older"])
    }

    @Test func singleRowHasNoLine() {
        #expect(KhalaTimelineLine.strokes([.now]) == [.init(above: .none, below: .none)])
        #expect(KhalaTimelineLine.strokes([]).isEmpty)
    }

    @Test func latestFirstPutsUndatedLast() {
        let items: [(String, Date?)] = [
            ("never", nil), ("soon", Self.base), ("friday", Self.base.addingTimeInterval(86400 * 3)), ("off", nil),
        ]
        #expect(KhalaTimelineLine.latestFirst(items, date: \.1).map(\.0) == ["friday", "soon", "never", "off"])
    }

    @Test func cameraTimelineAutomationsAboveNowDetectionsBelow() {
        func automation(_ id: String, _ minutes: Double?) -> KhalaDeviceAutomation {
            KhalaDeviceAutomation(
                automationId: id, name: id, description: nil, isEnabled: true,
                fireDates: minutes.map { [Self.base.addingTimeInterval($0 * 60)] } ?? [],
                timesOfDay: [], runMinutes: nil, targetsDevice: true
            )
        }
        func detection(_ minutes: Double) -> KhalaDetection {
            KhalaDetection(eventEntityId: "event.gate_person", date: Self.base.addingTimeInterval(minutes * 60),
                           noun: "Person", source: "Field detection")
        }
        let order = KhalaCameraTimelineRow.order(
            upcoming: [automation("automation.night_watch", 600), automation("automation.dusk", 120),
                       automation("automation.weekly", nil)],
            past: [detection(-5), detection(-240)]
        )
        let ids = order.rows.map { row -> String in
            switch row.item {
            case nil: return "NOW"
            case let .automation(automation)?: return automation.automationId
            case let .detection(detection)?: return "-\(Int(Self.base.timeIntervalSince(detection.date) / 60))m"
            }
        }
        #expect(ids == ["automation.night_watch", "automation.dusk", "NOW", "-5m", "-240m"])
    }

    @Test func carSubtitleSaysTheRefreshIsRunningUntilItIsDone() {
        let now = Self.base
        let justPressed = now.addingTimeInterval(-2)
        #expect(KhalaCarSyncState.waking.freshnessText(lastUpdated: justPressed, now: now) == KhalaScreenText.wakingCar)
        #expect(KhalaCarSyncState.updating.freshnessText(lastUpdated: justPressed, now: now) == KhalaScreenText.updating)
        #expect(KhalaCarSyncState.didntWake.freshnessText(lastUpdated: justPressed, now: now) == KhalaScreenText.carDidntWake)
        #expect(KhalaCarSyncState.idle.freshnessText(lastUpdated: justPressed, now: now) == "Updated just now")
        #expect(KhalaCarSyncState.idle.freshnessText(lastUpdated: nil, now: now) == nil)
    }

    @Test func aLockOfUnknownStateIsQuietAndDisabled() throws {
        for state in ["unknown", "unavailable"] {
            let lock = KhalaScreenFixtures.entity("lock.rover_lock", state, ["friendly_name": "Rover Lock"], device: "dev-r")
            let control = try #require(KhalaControl.make(lock, attributes: [:]))
            #expect(control.stateText == KhalaControl.unknownStateText)
            #expect(control.call == nil)
            #expect(!control.isActive)
        }
        let locked = KhalaScreenFixtures.entity("lock.rover_lock", "locked", ["friendly_name": "Rover Lock"], device: "dev-r")
        let control = try #require(KhalaControl.make(locked, attributes: [:]))
        #expect(control.stateText == "Locked")
        #expect(control.call?.service == "unlock")
    }
}
