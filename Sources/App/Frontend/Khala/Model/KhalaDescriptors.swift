import Foundation

/// The built-in descriptor table (DESCRIPTORS-DESIGN.md §1): one entry per kind, and the entity-level matching.
/// Integration-specific knowledge is NOT here; it is data (the hints file, a later slice).
///
/// Slice 1 only defines the table and the matching, tested over synthetic fixtures; detection still runs through
/// `KhalaDeviceCatalog`'s rules, which this table reproduces for the kinds detected today.
enum KhalaDescriptors {
    static let generic = KhalaDescriptor(
        kind: .generic, accent: .neutral, match: KhalaMatch(domains: []), deviceRule: nil, primary: .none,
        priority: 0, fallbackSymbol: "powerplug"
    )

    /// Highest priority first.
    static let all: [KhalaDescriptor] = [
        KhalaDescriptor(
            kind: .car, accent: .car, match: KhalaMatch(domains: ["device_tracker"]),
            deviceRule: .composite(all: ["device_tracker"], any: ["lock", "climate"]), primary: .none,
            priority: 100, fallbackSymbol: "car"
        ),
        KhalaDescriptor(
            kind: .waterHeater, accent: .heat, match: KhalaMatch(domains: ["water_heater"]), deviceRule: .face,
            primary: .toggle, priority: 90, fallbackSymbol: "drop"
        ),
        KhalaDescriptor(
            kind: .climate, accent: .heat, match: KhalaMatch(domains: ["climate"]), deviceRule: .face,
            primary: .none, priority: 80, fallbackSymbol: "thermometer.medium"
        ),
        KhalaDescriptor(
            kind: .media, accent: .media, match: KhalaMatch(domains: ["media_player"]), deviceRule: .face,
            primary: .toggle, priority: 70, fallbackSymbol: "tv"
        ),
        KhalaDescriptor(
            kind: .vacuum, accent: .neutral, match: KhalaMatch(domains: ["vacuum"]), deviceRule: .face,
            primary: .none, priority: 60, fallbackSymbol: "sparkles"
        ),
        KhalaDescriptor(
            kind: .lock, accent: .security, match: KhalaMatch(domains: ["lock"]), deviceRule: .face,
            primary: .lock, priority: 55, fallbackSymbol: "lock"
        ),
        KhalaDescriptor(
            kind: .cover, accent: .neutral, match: KhalaMatch(domains: ["cover"]), deviceRule: .face,
            primary: .open, priority: 50, fallbackSymbol: "blinds.horizontal.closed"
        ),
        KhalaDescriptor(
            kind: .fan, accent: .neutral, match: KhalaMatch(domains: ["fan"]), deviceRule: .face,
            primary: .toggle, priority: 45, fallbackSymbol: "fanblades"
        ),
        KhalaDescriptor(
            kind: .lightGroup, accent: .sun, match: KhalaMatch(domains: ["light"], requires: .entityGroup),
            deviceRule: .face, primary: .toggle, priority: 41, fallbackSymbol: "lightbulb.2"
        ),
        KhalaDescriptor(
            kind: .light, accent: .sun, match: KhalaMatch(domains: ["light"]), deviceRule: .face,
            primary: .toggle, priority: 40, fallbackSymbol: "lightbulb"
        ),
        KhalaDescriptor(
            kind: .switch, accent: .neutral, match: KhalaMatch(domains: ["switch", "input_boolean"]),
            deviceRule: .face, primary: .toggle, priority: 10, fallbackSymbol: "powerplug"
        ),
        KhalaDescriptor(
            kind: .camera, accent: .security, match: KhalaMatch(domains: ["camera"]), deviceRule: nil,
            primary: .none, priority: 0, fallbackSymbol: "video"
        ),
        generic,
    ]

    private static let byKind = Dictionary(all.map { ($0.kind, $0) }, uniquingKeysWith: { first, _ in first })

    static func descriptor(of kind: KhalaKind) -> KhalaDescriptor? {
        byKind[kind]
    }

    /// The most specific descriptor whose match passes for `entity`; ties go to the higher priority. Never nil:
    /// `generic` matches everything.
    static func descriptor(for entity: KhalaEntity, attributes: [String: Any]) -> KhalaDescriptor {
        all
            .filter { $0.match.matches(entity, attributes: attributes) }
            .max { lhs, rhs in
                if lhs.match.specificity != rhs.match.specificity {
                    return lhs.match.specificity < rhs.match.specificity
                }
                return lhs.priority < rhs.priority
            } ?? generic
    }
}
