import Foundation

/// A user's choice to show one entity as a device of a given kind (and optionally a label and a colour), e.g. a
/// plain relay switch as "Hot water", a water heater. Types are code (`KhalaKind`, `KhalaAccent`); which entity
/// plays which part is data, stored per server by `KhalaRoleAssignmentStore`.
///
/// Storage stays readable both ways: it is written with the new `kind` (and `accent` when it differs from the
/// kind's own) AND the legacy `role` string, so an older build still finds its pins; a pin stored before kinds
/// existed (only `role`) is mapped by `KhalaAccent.kind(forDomain:)`. An unknown role reads as `neutral`
/// instead of losing every pin.
struct KhalaRoleAssignment: Codable, Equatable, Identifiable {
    var entityId: String
    var kind: KhalaKind
    /// A colour other than the kind's own; nil = the kind's.
    var accent: KhalaAccent?
    /// Overrides the entity's friendly name in Khala when set and not blank.
    var label: String?

    var id: String { entityId }

    init(entityId: String, kind: KhalaKind, accent: KhalaAccent? = nil, label: String?) {
        self.entityId = entityId
        self.kind = kind
        self.accent = accent == kind.accent ? nil : accent
        self.label = label
    }

    /// A pin from a legacy role, as the device settings' role picker still makes them.
    init(entityId: String, role: KhalaAccent, label: String?) {
        let kind = role.kind(forDomain: Self.domain(of: entityId))
        self.init(entityId: entityId, kind: kind, accent: role, label: label)
    }

    /// The role (colour family) the device settings picker shows and sets. Setting it picks the kind that role
    /// stands for on this entity's domain.
    var role: KhalaAccent {
        get { accent ?? kind.accent }
        set {
            kind = newValue.kind(forDomain: Self.domain(of: entityId))
            accent = newValue == kind.accent ? nil : newValue
        }
    }

    /// The label to show, or nil when the entity's own name should be used.
    var displayLabel: String? {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else { return nil }
        return label
    }

    private static func domain(of entityId: String) -> String {
        entityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? entityId
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case entityId, role, kind, accent, label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entityId = try container.decode(String.self, forKey: .entityId)
        let label = try container.decodeIfPresent(String.self, forKey: .label)
        if let kind = try container.decodeIfPresent(KhalaKind.self, forKey: .kind) {
            let accent = (try? container.decodeIfPresent(String.self, forKey: .accent)).flatMap(KhalaAccent.init)
            self.init(entityId: entityId, kind: kind, accent: accent, label: label)
        } else {
            let role = try container.decode(String.self, forKey: .role)
            self.init(entityId: entityId, role: KhalaAccent(rawValue: role) ?? .neutral, label: label)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entityId, forKey: .entityId)
        try container.encode(role, forKey: .role)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(accent, forKey: .accent)
        try container.encodeIfPresent(label, forKey: .label)
    }
}
