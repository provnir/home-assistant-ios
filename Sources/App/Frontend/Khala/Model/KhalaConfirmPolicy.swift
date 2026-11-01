import Foundation

/// Which actions always ask first, decided from the entity's own data (its domain and device class), never from a
/// name and never from whether a screen remembered to declare it (DESCRIPTORS-DESIGN.md §4, slice 4: confirmation
/// must never be skipped):
/// - **a lock**: unlocking by any route (`unlock`; `turn on`/`toggle`, which upstream `Domain` maps to unlock) and
///   opening it (`lock.open`, the latch);
/// - **a cover that guards a way in** (a garage door, a gate, a door, or a cover that doesn't say what it is):
///   opening it by any route (`open`, `turn on`, `toggle`, the Open command, or a position above where it is now —
///   any position while that is unknown).
/// Closing and locking never ask. Window coverings (blinds, curtains, shades, shutters, awnings, windows, dampers)
/// don't ask on their own; a screen may still declare a confirmation for one (the car's tiles ask before opening any
/// cover, as in 41.1).
enum KhalaConfirmPolicy {
    /// Cover device classes that only cover a window or a vent: opening one lets nobody in.
    static let quietCoverClasses: Set<String> = ["awning", "blind", "curtain", "damper", "shade", "shutter", "window"]

    /// Whether opening a cover of `deviceClass` asks first.
    static func asksBeforeOpening(coverClass deviceClass: String?) -> Bool {
        !quietCoverClasses.contains(deviceClass ?? "")
    }

    /// The question to ask before `intent` on an entity of `domain`, or nil when it may go at once.
    /// - Parameter position: a cover's current position (0 closed … 100 open), nil when it reports none.
    static func required(
        _ intent: KhalaIntent,
        domain: String,
        deviceClass: String?,
        position: Double?
    ) -> KhalaConfirm? {
        let intent = intent.unconfirmed
        switch domain {
        case "lock":
            switch intent {
            case .unlock, .setOn(true), .toggle: return .unlock
            case .open, .command(.open): return .open(deviceClass: deviceClass)
            default: return nil
            }
        case "cover":
            guard asksBeforeOpening(coverClass: deviceClass), opens(intent, from: position) else { return nil }
            return .open(deviceClass: deviceClass)
        default:
            return nil
        }
    }

    /// Whether `intent` opens a cover now at `position` (or might: a toggle, an unknown position).
    static func opens(_ intent: KhalaIntent, from position: Double?) -> Bool {
        switch intent.unconfirmed {
        case .open, .setOn(true), .toggle, .command(.open): return true
        case let .set(.position, value):
            guard let position else { return true }
            return value > position
        default: return false
        }
    }
}
