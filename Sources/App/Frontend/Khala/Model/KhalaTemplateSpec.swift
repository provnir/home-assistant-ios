import Foundation

/// The screen a kind gets (DESCRIPTORS-DESIGN.md §3): a hero on top, then sections. Lights and fans came with slice
/// 3, climate, covers and locks with slice 4; the vacuum hero joins with its slice. Car, water heater and cameras keep their
/// bespoke screens and are not described by a template yet.
struct KhalaTemplateSpec: Equatable {
    enum Hero: Equatable {
        /// The generic screen's top: a Power card when the face switches, else the face's own tile.
        case status
        /// Power, brightness, warmth and colour as the light supports them; a group adds its members.
        case light
        /// Power, speed (snapping to the fan's step), oscillation, direction and preset as the fan supports them.
        case fan
        /// Target stepper, HVAC mode, then fan mode, preset and swing as the climate supports them.
        case climate
        /// Open / Stop / Close, position and tilt as the cover supports them; opening a way in asks first.
        case cover
        /// Lock / Unlock…, and Open… when the lock can pull its latch; unlocking and opening always ask.
        case lock
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
    static let climate = KhalaTemplateSpec(hero: .climate, sections: [.controls, .readings, .attributes])
    static let cover = KhalaTemplateSpec(hero: .cover, sections: [.controls, .readings, .attributes])
    static let lock = KhalaTemplateSpec(hero: .lock, sections: [.controls, .readings, .attributes])
}
