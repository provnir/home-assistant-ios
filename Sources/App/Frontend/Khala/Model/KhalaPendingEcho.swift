import Foundation

/// What in Home Assistant's live state proves a pending call landed, so the optimistic overlay can step aside for
/// the real state (`KhalaPendingBook.reconcile`).
enum KhalaPendingEcho: Equatable {
    /// The state is one of these (`on`; `open`/`opening` — a moving cover already proves the command landed, as
    /// upstream `Domain.statesAfter` says).
    case state(Set<String>)
    /// The state is none of these (a climate turned on lands in whichever hvac mode it picks).
    case notState(Set<String>)
    /// The state read as a number (`number.*`).
    case stateNumber(Double, tolerance: Double)
    case attributeNumber(String, Double, tolerance: Double)
    case attributeString(String, String)
    /// Nothing to wait for (a button press): the entry ends with Home Assistant's answer.
    case none

    /// Whether `entity` with `attributes` shows the change.
    func isEchoed(by entity: KhalaEntity?, attributes: [String: Any]) -> Bool {
        guard let entity else { return false }
        switch self {
        case let .state(states): return states.contains(entity.state)
        case let .notState(states): return !states.contains(entity.state)
        case let .stateNumber(value, tolerance):
            guard let number = Double(entity.state) else { return false }
            return abs(number - value) <= tolerance
        case let .attributeNumber(key, value, tolerance):
            guard let number = KhalaValue.double(attributes[key]) else { return false }
            return abs(number - value) <= tolerance
        case let .attributeString(key, value): return KhalaValue.string(attributes[key]) == value
        case .none: return false
        }
    }

    /// The echo of turning an entity of `domain` on or off.
    static func power(domain: String, on: Bool) -> KhalaPendingEcho {
        switch domain {
        case "cover", "valve": return on ? .state(["open", "opening"]) : .state(["closed", "closing"])
        case "lock": return on ? .state(["locked", "locking"]) : .state(["unlocked", "unlocking", "open"])
        case "climate", "water_heater": return on ? .notState(["off", "unavailable", "unknown"]) : .state(["off"])
        case "media_player":
            return on ? .notState(["off", "standby", "unavailable", "unknown"]) : .state(["off", "standby"])
        default: return .state([on ? "on" : "off"])
        }
    }

    /// The echo of picking `option` for `field`.
    static func choice(_ field: KhalaChoiceField, _ option: String) -> KhalaPendingEcho {
        switch field {
        case .option, .hvacMode: return .state([option])
        case .source: return .attributeString("source", option)
        case .soundMode: return .attributeString("sound_mode", option)
        case .fanMode: return .attributeString("fan_mode", option)
        case .presetMode: return .attributeString("preset_mode", option)
        case .swingMode: return .attributeString("swing_mode", option)
        }
    }
}
