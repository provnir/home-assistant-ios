import Foundation

/// The optimistic-state machine behind `KhalaPendingStore`, Foundation-only so its rules are tested on Linux:
/// 1. `begin` at the tap: the control shows the new state at once. A second discrete tap on the same entity while
///    the first is still out, or within `throttle` of it, is refused (double-firing); a new number replaces the
///    old one (the views debounce those).
/// 2. `answer` with Home Assistant's reply: a refusal drops the entry (the control reverts); an acceptance starts
///    the `echoTimeout` clock.
/// 3. `reconcile` with each live update drops entries the state now shows, and `expire` drops answered entries
///    whose echo never came, so the control settles on the real state either way.
struct KhalaPendingBook: Equatable {
    /// How long an accepted call's value is shown without Home Assistant's state confirming it.
    static let echoTimeout: TimeInterval = 5
    /// The shortest gap between two discrete sends to one entity.
    static let throttle: TimeInterval = 1
    /// A call never answered (a lost socket) stops showing after this, whatever happens to it.
    static let inFlightLimit: TimeInterval = 120

    private(set) var entries: [String: KhalaPending] = [:]
    private var lastSent: [String: Date] = [:]

    /// Entries are keyed by `KhalaControlModel.id` (one per control, several per media player).
    func pending(_ key: String) -> KhalaPending? { entries[key] }

    /// Starts showing `value` on the control `key` of `entityId`. False when the tap is a double-fire and must not
    /// be sent.
    mutating func begin(
        _ key: String,
        entityId: String,
        value: KhalaPendingValue,
        echo: KhalaPendingEcho,
        now: Date
    ) -> Bool {
        let isNumber: Bool
        if case .number = value { isNumber = true } else { isNumber = false }
        if !isNumber {
            if entries[key]?.isInFlight == true { return false }
            if let last = lastSent[key], now.timeIntervalSince(last) < Self.throttle { return false }
        }
        entries[key] = KhalaPending(entityId: entityId, value: value, echo: echo, startedAt: now)
        lastSent[key] = now
        return true
    }

    /// Home Assistant's answer for control `key`'s call `startedAt`. A stale answer (a newer value replaced it) is
    /// ignored unless it is a refusal of the newest.
    mutating func answer(_ key: String, startedAt: Date, ok: Bool, now: Date) {
        guard var entry = entries[key], entry.startedAt == startedAt else { return }
        guard ok, entry.echo != .none, !entry.isEchoed else {
            entries[key] = nil
            return
        }
        entry.answeredAt = now
        entries[key] = entry
    }

    /// Drops what the live states show, and what has waited too long. True when anything changed.
    @discardableResult
    mutating func reconcile(entities: [String: KhalaEntity], attributes: [String: [String: Any]], now: Date) -> Bool {
        let before = entries
        for (key, entry) in entries
            where entry.echo.isEchoed(by: entities[entry.entityId], attributes: attributes[entry.entityId] ?? [:]) {
            if entry.isInFlight {
                entries[key]?.isEchoed = true
            } else {
                entries[key] = nil
            }
        }
        expire(now: now)
        return entries != before
    }

    /// Drops answered entries past `echoTimeout` and calls out longer than `inFlightLimit`.
    mutating func expire(now: Date) {
        entries = entries.filter { _, entry in
            if let answered = entry.answeredAt { return now.timeIntervalSince(answered) < Self.echoTimeout }
            return now.timeIntervalSince(entry.startedAt) < Self.inFlightLimit
        }
    }

    /// When the next entry runs out, for the store's timer.
    var nextExpiry: Date? {
        entries.values.map { entry in
            entry.answeredAt.map { $0.addingTimeInterval(Self.echoTimeout) }
                ?? entry.startedAt.addingTimeInterval(Self.inFlightLimit)
        }.min()
    }
}
