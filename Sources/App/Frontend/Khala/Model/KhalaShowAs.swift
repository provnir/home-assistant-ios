import Foundation

/// The device settings' "Show as…" picker (slice 5): which screen a pin opens is its kind's route
/// (`KhalaScreenRoute`), so the kind is picked on its own instead of following the role. The role still picks the
/// colour, and a starting kind when it changes (`KhalaRoleAssignment.role`); "Show as…" then overrides the kind and
/// keeps the colour. For kinds that open the template screen, the panel follows the entity itself (a light's
/// panel needs a light).
extension KhalaKind {
    /// What the picker offers, in order: the bespoke screens first, then the template kinds, then "Other".
    static let showAsChoices: [KhalaKind] = [
        .car, .waterHeater, .media, .camera, .climate, .light, .fan, .cover, .lock, .switch, .generic,
    ]

    /// The picker's rows for a pin of `current` kind: `showAsChoices`, plus `current` at the end when it is not
    /// one of them (a light group, a kind from an HA label or a newer build), so the picker always shows it.
    static func showAsChoices(including current: KhalaKind) -> [KhalaKind] {
        showAsChoices.contains(current) ? showAsChoices : showAsChoices + [current]
    }

    /// The kind's name in the picker.
    var displayName: String {
        switch self {
        case .car: return "Car"
        case .waterHeater: return "Water heater"
        case .climate: return "Climate"
        case .media: return "Media"
        case .vacuum: return "Vacuum"
        case .lock: return "Lock"
        case .cover: return "Cover"
        case .fan: return "Fan"
        case .light: return "Light"
        case .lightGroup: return "Light group"
        case .switch: return "Switch"
        case .camera: return "Camera"
        case .generic: return "Other"
        default: return rawValue
        }
    }
}

extension KhalaRoleAssignment {
    /// The kind the pin is shown as. Setting it keeps the pin's colour (its role) and changes only the screen.
    var showAs: KhalaKind {
        get { kind }
        set {
            let colour = role
            kind = newValue
            accent = colour == newValue.accent ? nil : colour
        }
    }
}
