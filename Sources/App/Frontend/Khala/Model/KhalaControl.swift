import Foundation

/// One tile of a device's controls grid (lock, sentry switch, charge port, frunk, flash lights, a seat heater...):
/// what it shows and the action a tap makes. Built from an entity of the device, so a device only gets tiles for
/// what it actually exposes.
struct KhalaControl: Equatable, Identifiable {
    enum Glyph: String, Equatable {
        case lock, unlock, shield, chargePort, frunk, trunk, window, lights, horn, power, seat, wheel, defrost
        case fan, button, generic

        /// The SF Symbol a tile draws for this glyph (moved here from `KhalaControlTile`, unchanged).
        var symbolName: String {
            switch self {
            case .lock: return "lock.fill"
            case .unlock: return "lock.open.fill"
            case .shield: return "shield.fill"
            case .chargePort: return "bolt.fill"
            case .frunk, .trunk: return "car.rear"
            case .window: return "arrow.up.doc"
            case .lights: return "lightbulb.fill"
            case .horn: return "speaker.wave.2.fill"
            case .power: return "power"
            case .seat: return "flame.fill"
            case .wheel: return "dial"
            case .defrost: return "sparkles"
            case .fan: return "fanblades"
            case .button: return "circle.circle"
            case .generic: return "slider.horizontal.3"
            }
        }
    }

    let entityId: String
    let title: String
    /// The state under or instead of the title ("Locked", "On", "Open").
    let stateText: String
    let glyph: Glyph
    /// Drawn tinted (locked, on, open).
    let isActive: Bool
    /// What a tap does; nil when nothing can be done from here (e.g. a frunk that only opens, already open).
    let call: KhalaServiceCallPlan?
    /// `select.*`: the choices, offered as a menu; a pick calls `select.select_option`.
    let options: [String]
    /// Asks before acting (unlocking, opening).
    let needsConfirmation: Bool

    var id: String { entityId }

    /// What a tile whose state isn't known yet reads.
    static let unknownStateText = "…"
}

extension KhalaControl {
    /// A tile for `entity`, or nil for domains that make no tile.
    static func make(_ entity: KhalaEntity, attributes: [String: Any], hints: KhalaHints = .builtIn) -> KhalaControl? {
        let title = entity.nameWithoutDevice
        let glyph = glyph(for: entity, hints: hints)
        // Only `unavailable` blocks a tap: buttons sit at `unknown` until first pressed.
        let unavailable = entity.state == "unavailable"
        switch entity.domain {
        case "lock":
            let locked = entity.state == "locked"
            // Unknown while a sleeping car wakes (build 24.1 showed "—"): a quiet "…", no action, the tile's
            // disabled look, until the refresh lands and it reads Locked/Unlocked.
            let unknown = ["unknown", "unavailable", ""].contains(entity.state)
            return KhalaControl(
                entityId: entity.entityId,
                title: title,
                stateText: unknown ? KhalaControl.unknownStateText : KhalaText.humanized(state: entity.state),
                glyph: locked || unknown ? .lock : .unlock,
                isActive: locked,
                call: unknown ? nil : KhalaServiceCallPlan(domain: "lock", service: locked ? "unlock" : "lock",
                                                           entityId: entity.entityId),
                options: [],
                needsConfirmation: locked
            )
        case "switch", "input_boolean", "fan", "light":
            let on = entity.state == "on"
            return KhalaControl(
                entityId: entity.entityId,
                title: title,
                stateText: KhalaText.humanized(state: entity.state),
                glyph: glyph,
                isActive: on,
                call: unavailable ? nil : KhalaServiceCallPlan(domain: entity.domain, service: on ? "turn_off" : "turn_on",
                                                               entityId: entity.entityId),
                options: [],
                needsConfirmation: false
            )
        case "cover":
            // CoverEntityFeature: OPEN = 1, CLOSE = 2.
            let features = KhalaValue.int(attributes["supported_features"]) ?? 3
            let closed = entity.state == "closed"
            let service: String? = closed
                ? (features & 1 != 0 ? "open_cover" : nil)
                : (features & 2 != 0 ? "close_cover" : nil)
            return KhalaControl(
                entityId: entity.entityId,
                title: title,
                stateText: KhalaText.humanized(state: entity.state),
                glyph: glyph,
                isActive: !closed && !unavailable,
                call: unavailable ? nil : service.map { KhalaServiceCallPlan(domain: "cover", service: $0, entityId: entity.entityId) },
                options: [],
                needsConfirmation: closed
            )
        case "button":
            return KhalaControl(
                entityId: entity.entityId,
                title: title,
                stateText: "",
                glyph: glyph,
                isActive: false,
                call: unavailable ? nil : KhalaServiceCallPlan(domain: "button", service: "press", entityId: entity.entityId),
                options: [],
                needsConfirmation: false
            )
        case "select", "input_select":
            let options = KhalaValue.list(attributes["options"]).compactMap { $0 as? String }
            return KhalaControl(
                entityId: entity.entityId,
                title: title,
                stateText: KhalaText.humanized(state: entity.state),
                glyph: glyph,
                isActive: !["off", "unavailable", "unknown"].contains(entity.state),
                call: nil,
                options: unavailable ? [] : options,
                needsConfirmation: false
            )
        default:
            return nil
        }
    }

    /// The glyph for an entity: a lock's state, else its hint's glyph (`KhalaHints`, keyed on platform and
    /// translation key), else its device class and domain. Names and ids are never read.
    static func glyph(for entity: KhalaEntity, hints: KhalaHints = .builtIn) -> Glyph {
        if entity.domain == "lock" { return entity.state == "locked" ? .lock : .unlock }
        if let glyph = hints.hint(for: entity)?.glyph { return glyph }
        if entity.deviceClass == "window" { return .window }
        switch entity.domain {
        case "light": return .lights
        case "fan", "climate": return .fan
        case "button": return .button
        case "switch": return .power
        default: return .generic
        }
    }
}
