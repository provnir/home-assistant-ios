import Foundation

/// Reads Home Assistant's recorder history and turns it into what the device screens list: detections, on-runs
/// and arrivals/departures.
///
/// `history/history_during_period` answers `{entity_id: [{"s": state, "a": attributes, "lu": epoch, "lc": epoch}]}`
/// (compressed states; `a` is left out with `no_attributes`, `lc` when it equals `lu`) — HA core
/// `components/history/websocket_api.py` and `components/recorder/models/state.py` (`row_to_compressed_state`).
enum KhalaHistory {
    static func parse(_ response: [String: Any]) -> [String: [KhalaHistoryState]] {
        var result: [String: [KhalaHistoryState]] = [:]
        for (entityId, value) in response {
            let states: [KhalaHistoryState] = KhalaValue.dictionaries(value).compactMap { row in
                guard let state = KhalaValue.string(row["s"]) ?? (row["s"] as? String),
                      let stamp = KhalaValue.double(row["lu"]) ?? KhalaValue.double(row["lc"]) else { return nil }
                let attributes = row["a"] as? [String: Any]
                return KhalaHistoryState(
                    state: state,
                    date: Date(timeIntervalSince1970: stamp),
                    eventType: KhalaValue.string(attributes?["event_type"])
                )
            }
            result[entityId] = states.sorted { $0.date < $1.date }
        }
        return result
    }

    /// The stretches an on/off entity spent on, newest first. A state other than off/unavailable/unknown counts as
    /// on (water heaters report their operation mode as the state). `unavailable` ends a run without starting one.
    static func runs(_ states: [KhalaHistoryState], now: Date) -> [KhalaRun] {
        var runs: [KhalaRun] = []
        var start: Date?
        for item in states.sorted(by: { $0.date < $1.date }) {
            let isOn = !["off", "unavailable", "unknown", ""].contains(item.state)
            if isOn, start == nil {
                start = item.date
            } else if !isOn, let began = start {
                runs.append(KhalaRun(start: began, end: item.date))
                start = nil
            }
        }
        if let start, start <= now {
            runs.append(KhalaRun(start: start, end: nil))
        }
        return runs.reversed()
    }

    /// Arrivals and departures of a `device_tracker`/`person`, newest first. GPS noise between two away states
    /// (`not_home` → `not_home`) is not a change; unknown/unavailable are skipped.
    static func presenceChanges(_ states: [KhalaHistoryState]) -> [KhalaPresenceChange] {
        var changes: [KhalaPresenceChange] = []
        var previous: String?
        for item in states.sorted(by: { $0.date < $1.date }) {
            guard !["unknown", "unavailable", ""].contains(item.state) else { continue }
            defer { previous = item.state }
            guard let before = previous, before != item.state else { continue }
            if item.state == "not_home" {
                changes.append(KhalaPresenceChange(date: item.date, arrived: false, place: before))
            } else {
                changes.append(KhalaPresenceChange(date: item.date, arrived: true, place: item.state))
            }
        }
        return changes.reversed()
    }
}
