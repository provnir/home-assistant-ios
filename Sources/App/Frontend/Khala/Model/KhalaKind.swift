import Foundation

/// What a thing IS (a light, a cover, a car…): drives the glyph fallback, the controls, the screen template and the
/// sort order through its `KhalaDescriptor`. Its colour is a separate `KhalaAccent`.
///
/// A string-backed value rather than an enum so a kind written by a newer build, a hints file or an HA label
/// (`khala:kind:<kind>`) always decodes; one Khala doesn't know reads as `generic` (`descriptor`). Raw values are
/// snake_case, like Home Assistant's own identifiers, and are persisted, so they never change.
struct KhalaKind: Hashable, Codable, RawRepresentable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue }

    static let car = KhalaKind(rawValue: "car")
    static let waterHeater = KhalaKind(rawValue: "water_heater")
    static let climate = KhalaKind(rawValue: "climate")
    static let media = KhalaKind(rawValue: "media")
    static let vacuum = KhalaKind(rawValue: "vacuum")
    static let lock = KhalaKind(rawValue: "lock")
    static let cover = KhalaKind(rawValue: "cover")
    static let fan = KhalaKind(rawValue: "fan")
    static let light = KhalaKind(rawValue: "light")
    static let lightGroup = KhalaKind(rawValue: "light_group")
    static let `switch` = KhalaKind(rawValue: "switch")
    /// Routing only: cameras keep their bespoke screens.
    static let camera = KhalaKind(rawValue: "camera")
    static let generic = KhalaKind(rawValue: "generic")

    /// This kind's built-in descriptor; `generic`'s for a kind Khala doesn't know.
    var descriptor: KhalaDescriptor {
        KhalaDescriptors.descriptor(of: self) ?? KhalaDescriptors.generic
    }

    /// Whether Khala has a descriptor for this kind.
    var isKnown: Bool {
        KhalaDescriptors.descriptor(of: self) != nil
    }

    /// The colour family the kind borrows.
    var accent: KhalaAccent {
        descriptor.accent
    }
}
