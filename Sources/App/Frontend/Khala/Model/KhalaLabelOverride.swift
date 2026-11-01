import Foundation

/// A correction Nir makes from Home Assistant itself by labelling an entity (decision 2, 2026-11-01): `khala:hide`
/// keeps it out of Khala, `khala:kind:<kind>` shows it as that kind. Data, not code: parsed from the registry's
/// `labels`, which hold label *ids* — HA slugifies a label's name into its id
/// (`khala:kind:light` → `khala_kind_light`), so both spellings are read. An unknown kind is ignored. Slice 1 parses; applying them comes with detection.
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
}
