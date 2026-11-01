import Foundation

/// The pre-descriptor name of `KhalaAccent`, kept as a thin alias while the screens move to `KhalaKind` and
/// descriptors (DESCRIPTORS-DESIGN.md §4): a category is a colour family, and the user-facing *role* picker in the
/// device settings still offers these families. The role helpers below are that legacy layer; each role maps to
/// one kind (`kind(forDomain:)`), and the kind's default accent is the role again, so pins round-trip.
typealias KhalaCategory = KhalaAccent

extension KhalaAccent {
    /// The roles a user can give a device in the device settings, in display order.
    static var assignableRoles: [KhalaCategory] {
        [.car, .heat, .media, .security, .neutral]
    }

    /// Order in which categories fill the Now card when nothing is pinned.
    static var chipPriority: [KhalaCategory] {
        [.car, .heat, .media, .security, .neutral]
    }

    /// A starting role for an entity the user just pinned, from its domain; the user can change it.
    static func suggestedRole(forDomain domain: String) -> KhalaCategory {
        switch domain {
        case "water_heater", "climate", "boiler": return .heat
        case "media_player", "remote": return .media
        case "camera", "event", "alarm_control_panel", "lock": return .security
        case "device_tracker": return .car
        default: return .neutral
        }
    }

    var displayName: String {
        switch self {
        case .security: return "Security"
        case .car: return "Car"
        case .heat: return "Hot water / heat"
        case .media: return "Media"
        case .sun: return "Sun"
        case .neutral: return "Other"
        }
    }

    /// The kind a legacy role stands for on an entity of `domain` (the decode of pins stored before kinds existed):
    /// heat → water heater, media → media, security → lock for a lock and camera otherwise, car → car,
    /// neutral → switch. `sun` was never assignable; it reads as generic.
    func kind(forDomain domain: String) -> KhalaKind {
        switch self {
        case .heat: return .waterHeater
        case .media: return .media
        case .security: return domain == "lock" ? .lock : .camera
        case .car: return .car
        case .neutral: return .switch
        case .sun: return .generic
        }
    }
}
