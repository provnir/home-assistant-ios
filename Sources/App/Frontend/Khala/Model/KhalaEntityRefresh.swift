import Foundation

/// Asking Home Assistant to poll a device again (`homeassistant.update_entity`), for screens whose data the
/// integration only refreshes now and then — a car's (build 19.1: "car data never refreshes"). One call names the
/// device's entities; a coordinator-based integration answers it with one refresh of its coordinator (its
/// `async_request_refresh` is debounced), a polling one polls each entity. A sleeping car is woken first
/// (`KhalaCarWakePlan`); `update_entity` itself only reads, so buttons, events, updates, scenes and scripts are
/// left out of the call.
enum KhalaEntityRefresh {
    /// Domains never named in a refresh.
    static let skippedDomains: Set<String> = ["button", "event", "update", "scene", "script", "notify", "image", "tts"]

    /// The entities of a device to name in one `homeassistant.update_entity` call, sorted.
    static func entityIds(of members: [KhalaEntity]) -> [String] {
        members.filter { !skippedDomains.contains($0.domain) }.map(\.entityId).sorted()
    }

    /// When the device's data last arrived: the newest `last_updated` among the entities a refresh names (a button's
    /// state is when it was last pressed, not news from the device).
    static func lastUpdated(of members: [KhalaEntity]) -> Date? {
        members.filter { !skippedDomains.contains($0.domain) }.map(\.lastUpdated).max()
    }
}

/// Keeps a device's refresh from double-firing: opening its screen again soon after a refresh completed doesn't
/// wake and poll it again; an explicit "Refresh now" always runs (but never two at once).
struct KhalaRefreshThrottle {
    /// An automatic refresh is skipped this soon after the last one completed.
    static let interval: TimeInterval = 60

    private(set) var completed: [String: Date] = [:]
    private(set) var running: Set<String> = []

    /// Whether opening the screen should refresh `key` now.
    func allowsAutomatic(_ key: String, now: Date) -> Bool {
        guard !running.contains(key) else { return false }
        guard let last = completed[key], now >= last else { return true }
        return now.timeIntervalSince(last) >= Self.interval
    }

    /// Marks a refresh of `key` as running; false when one already is.
    mutating func begin(_ key: String) -> Bool {
        running.insert(key).inserted
    }

    /// Marks it done; a completed one holds automatic refreshes back for `interval`, a failed one doesn't.
    mutating func finish(_ key: String, now: Date, completed didComplete: Bool) {
        running.remove(key)
        if didComplete { completed[key] = now }
    }
}
