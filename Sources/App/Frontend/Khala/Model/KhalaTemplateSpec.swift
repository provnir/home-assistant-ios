import Foundation

/// The screen a kind gets (DESCRIPTORS-DESIGN.md §3): a hero on top, then sections. Only the parts slice 3 draws are
/// here; climate, cover, lock and vacuum heroes join with their slices. Car, water heater and cameras keep their
/// bespoke screens and are not described by a template yet.
struct KhalaTemplateSpec: Equatable {
    enum Hero: Equatable {
        /// The generic screen's top: a Power card when the face switches, else the face's own tile.
        case status
        /// Power, brightness, warmth and colour as the light supports them; a group adds its members.
        case light
        /// Power, speed (snapping to the fan's step), oscillation, direction and preset as the fan supports them.
        case fan
    }

    enum Section: Equatable {
        /// A group's members, one row each (vertical, any length).
        case members
        /// Tiles for the device's other controllable entities.
        case controls
        /// The device's other entities as read-only rows.
        case readings
        /// The face's attributes.
        case attributes
    }

    var hero: Hero
    var sections: [Section]

    /// Plugs, relays, pinned entities, anything without a designed screen.
    static let generic = KhalaTemplateSpec(hero: .status, sections: [.controls, .readings, .attributes])
    static let light = KhalaTemplateSpec(hero: .light, sections: [.members, .controls, .readings, .attributes])
    static let fan = KhalaTemplateSpec(hero: .fan, sections: [.controls, .readings, .attributes])
}
