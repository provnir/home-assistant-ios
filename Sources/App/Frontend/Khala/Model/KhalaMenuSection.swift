import Foundation

/// The menu's DEVICES list, grouped by Home Assistant area once it grows (decision 1, 2026-11-01): pinned devices stay
/// on top without a header, then one section per area in Home Assistant's order (then by name), then devices with
/// no known area under "Other". A short list stays flat, as in 41.1. A search always shows a flat list of matches.
struct KhalaMenuSection: Equatable, Identifiable {
    /// The area id; `pinned` and `other` for the two sections without an area.
    let id: String
    /// nil = no header (the pinned devices, or the whole list while it is flat).
    let title: String?
    let devices: [KhalaDevice]

    static let pinnedId = "khala:pinned"
    static let otherId = "khala:other"
    static let allId = "khala:all"

    /// Above this many devices the list is grouped.
    static let groupingThreshold = 8

    static func sections(
        devices: [KhalaDevice],
        areas: [KhalaArea],
        query: String = "",
        threshold: Int = groupingThreshold
    ) -> [KhalaMenuSection] {
        let query = query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let matches = devices.filter { $0.name.localizedCaseInsensitiveContains(query) }
            return matches.isEmpty ? [] : [KhalaMenuSection(id: allId, title: nil, devices: matches)]
        }
        guard devices.count > threshold else {
            return devices.isEmpty ? [] : [KhalaMenuSection(id: allId, title: nil, devices: devices)]
        }
        let areasById = Dictionary(areas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [KhalaMenuSection] = []
        let pinned = devices.filter(\.isPinned)
        if !pinned.isEmpty {
            result.append(KhalaMenuSection(id: pinnedId, title: nil, devices: pinned))
        }
        let rest = devices.filter { !$0.isPinned }
        var byArea: [String: [KhalaDevice]] = [:]
        var other: [KhalaDevice] = []
        for device in rest {
            if let areaId = device.areaId, areasById[areaId] != nil {
                byArea[areaId, default: []].append(device)
            } else {
                other.append(device)
            }
        }
        let orderedAreas = byArea.keys.compactMap { areasById[$0] }.sorted { lhs, rhs in
            switch (lhs.sortOrder, rhs.sortOrder) {
            case let (left?, right?) where left != right: return left < right
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
        for area in orderedAreas {
            result.append(KhalaMenuSection(id: area.id, title: area.name, devices: byArea[area.id] ?? []))
        }
        if !other.isEmpty {
            result.append(KhalaMenuSection(id: otherId, title: KhalaText.otherDevices, devices: other))
        }
        return result
    }
}
