import Foundation

/// The "tad of color" families of the Khala design (DESIGN.md, Tokens). One muted accent per family, used only on
/// timeline dots, small glyph chips and active controls. Also the user-assignable *role* of a device: the role is
/// what picks its glyph and accent, so a switch the user marks as `heat` reads as hot water everywhere.
///
/// Foundation-only on purpose (no SwiftUI): colours and glyphs live in `KhalaTheme`.
enum KhalaCategory: String, Codable, CaseIterable, Equatable {
    /// Cameras and security.
    case security
    case car
    /// Water heaters, boilers and other heat sources.
    case heat
    /// Theater, speakers and other media players.
    case media
    /// Sunrise and sunset. Never a device role.
    case sun
    /// Anything else (plugs, relays, unclassified automations).
    case neutral

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
}
