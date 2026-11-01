import Foundation

/// One read of Home Assistant's recorder for a device screen (DESCRIPTORS-DESIGN.md §4 row 6): which entities, how
/// far back, and what the screen makes of the answer. A camera's events, the car's arrivals and departures and the
/// boiler's on-runs all go through this one type and `KhalaScreenActions.history(_:)`; before slice 6 each screen
/// built its own window, message and parser.
///
/// The message is `history/history_during_period` (HA core `components/history/websocket_api.py`), every change
/// included, with the state in force at the window's start. Attributes are sent only for `events`, the one shape
/// that reads them (a detection's `event_type`); arrivals and on-runs read states alone, so a tracker's GPS
/// attributes never cross the wire.
struct KhalaHistoryRequest: Hashable {
    enum Shape: Hashable {
        /// `event.*` firings with their event types: a camera's detections (`KhalaCameraCatalog.detections`).
        case events
        /// A tracker's arrivals and departures, newest first (`KhalaHistory.presenceChanges`).
        case presence
        /// The stretches an entity spent on, newest first (`KhalaHistory.runs`).
        case runs
    }

    let entityIds: [String]
    /// How far back from now the read goes.
    let window: TimeInterval
    let shape: Shape
    /// The most items the screen lists (nil: all of them).
    let limit: Int?

    static let day: TimeInterval = 86400
    /// How far back a camera's Events tab reads and lists.
    static let cameraEventsWindow: TimeInterval = 7 * day

    /// A camera's event entities over the last week: the Events tab, and today's detections on the Live tab.
    static func cameraEvents(_ eventEntityIds: [String]) -> KhalaHistoryRequest {
        KhalaHistoryRequest(entityIds: eventEntityIds, window: cameraEventsWindow, shape: .events, limit: nil)
    }

    /// The car's last four arrivals and departures, over three days.
    static func presence(of trackerId: String) -> KhalaHistoryRequest {
        KhalaHistoryRequest(entityIds: [trackerId], window: 3 * day, shape: .presence, limit: 4)
    }

    /// A heater's on-runs over the last week: the hot-water History tab.
    static func runs(of entityId: String) -> KhalaHistoryRequest {
        KhalaHistoryRequest(entityIds: [entityId], window: 7 * day, shape: .runs, limit: nil)
    }

    /// Where the window starts.
    func start(now: Date) -> Date {
        now.addingTimeInterval(-window)
    }

    /// The `history/history_during_period` message data.
    func message(now: Date) -> [String: Any] {
        [
            "start_time": ISO8601DateFormatter().string(from: start(now: now)),
            "entity_ids": entityIds,
            "include_start_time_state": true,
            "significant_changes_only": false,
            "minimal_response": false,
            "no_attributes": shape != .events,
        ]
    }

    // MARK: - What the screen shows

    /// The recorded states by entity id (`KhalaHistory.parse`), for the camera screen's detections.
    func states(from response: [String: Any]) -> [String: [KhalaHistoryState]] {
        KhalaHistory.parse(response)
    }

    /// The arrivals and departures of the request's tracker, newest first, at most `limit`.
    func presenceChanges(from states: [String: [KhalaHistoryState]]) -> [KhalaPresenceChange] {
        let changes = KhalaHistory.presenceChanges(entityIds.first.flatMap { states[$0] } ?? [])
        return limit.map { Array(changes.prefix($0)) } ?? changes
    }

    /// The on-runs of the request's entity, newest first, at most `limit`.
    func runs(from states: [String: [KhalaHistoryState]], now: Date) -> [KhalaRun] {
        let runs = KhalaHistory.runs(entityIds.first.flatMap { states[$0] } ?? [], now: now)
        return limit.map { Array(runs.prefix($0)) } ?? runs
    }
}
