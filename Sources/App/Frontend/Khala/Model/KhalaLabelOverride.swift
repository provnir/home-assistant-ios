import Foundation

/// A correction Nir makes from Home Assistant itself by labelling an entity (decision 2, 2026-11-01): `khala:hide`
/// keeps it out of Khala, `khala:kind:<kind>` shows it as that kind. Data, not code: parsed from the registry's
/// `labels`, which hold label *ids* — HA slugifies a label's name into its id
/// (`khala:kind:light` → `khala_kind_light`), so both spellings are read. An unknown kind is ignored. HA adds
/// `_2`, `_3`… to the id of a second label with the same name, and such an id does NOT match: name labels uniquely.
///
/// Applied by `KhalaDeviceCatalog` (a hidden entity is never a face nor a member of a listed device; a kind label
/// beats the built-in table), `KhalaTimeline` and the camera list. A user pin beats both.
enum KhalaLabelOverride: Equatable {
    case hide
    case kind(KhalaKind)

    static func overrides(labels: [String]) -> [KhalaLabelOverride] {
        labels.compactMap(parse)
    }

    static func parse(_ label: String) -> KhalaLabelOverride? {
        let normalized = label.lowercased().replacingOccurrences(of: ":", with: "_")
        if normalized == "khala_hide" { return .hide }
        let prefix = "khala_kind_"
        guard normalized.hasPrefix(prefix) else { return nil }
        let kind = KhalaKind(rawValue: String(normalized.dropFirst(prefix.count)))
        return kind.isKnown ? .kind(kind) : nil
    }

    /// Whether `entity` carries `khala:hide`.
    static func isHidden(_ entity: KhalaEntity) -> Bool {
        overrides(labels: entity.labels).contains(.hide)
    }

    /// The kind a `khala:kind:<kind>` label gives `entity`, if any (the first, when there are several).
    static func kind(of entity: KhalaEntity) -> KhalaKind? {
        for override in overrides(labels: entity.labels) {
            if case let .kind(kind) = override { return kind }
        }
        return nil
    }
}
