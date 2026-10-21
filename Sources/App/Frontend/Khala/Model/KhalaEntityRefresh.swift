import Foundation

/// Asking Home Assistant to poll a device again (`homeassistant.update_entity`), for screens whose data the
/// integration only refreshes now and then — a car's (build 19.1: "car data never refreshes"). One call names the
/// device's entities; a coordinator-based integration answers it with one refresh of its coordinator (its
/// `async_request_refresh` is debounced), a polling one polls each entity.
///
/// `update_entity` reads; it never acts. Still, only entities that report something are named: no buttons (a car's
/// wake button stays the person's to press — waking a car costs battery and is never automatic), no events,
/// updates, scenes or scripts.
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

/// At most one refresh per device per interval, so opening a screen repeatedly, or pulling to refresh, doesn't
/// hammer a cloud API (a car's integration usually has a rate limit).
struct KhalaRefreshThrottle {
    /// Opening the screen.
    static let onAppear: TimeInterval = 60
    /// Pull to refresh: asked for explicitly, so sooner.
    static let onPull: TimeInterval = 15

    private(set) var lastRequests: [String: Date] = [:]

    /// True (and remembered) when `key` may refresh now: never asked, or last asked at least `interval` ago.
    mutating func shouldRefresh(_ key: String, now: Date, interval: TimeInterval) -> Bool {
        if let last = lastRequests[key], now.timeIntervalSince(last) < interval, now >= last { return false }
        lastRequests[key] = now
        return true
    }
}
