import Foundation

/// Turns entity states into the devices Khala lists, without knowing any particular home: roles come from Home
/// Assistant data (domains present on a registry device, device classes) and from the user's role assignments.
///
/// Detection, per registry device (an entity without a device stands alone):
/// - **car**: has a `device_tracker` and a `lock` or `climate` (phones have trackers but no locks); shows the
///   battery sensor when there is one, else where the tracker is.
/// - **heat**: has a `water_heater`.
/// - **media**: has a `media_player` (receivers and TVs preferred as the face).
/// - **neutral**: a plain switchable thing — `switch` with none of the "bigger device" domains — e.g. a relay.
/// Cameras are not listed (the menu counts them under Cameras). Pinned assignments come first, in the user's
/// order, and take over the whole device they belong to.
enum KhalaDeviceCatalog {
    static func build(entities: [KhalaEntity], assignments: [KhalaRoleAssignment]) -> [KhalaDevice] {
        let groups = group(entities)
        let groupKeyByEntityId = groups.reduce(into: [String: String]()) { result, group in
            for member in group.members {
                result[member.entityId] = group.key
            }
        }
        let entitiesById = Dictionary(entities.map { ($0.entityId, $0) }, uniquingKeysWith: { first, _ in first })
        let groupsByKey = Dictionary(groups.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        var pinned: [KhalaDevice] = []
        var claimedGroups = Set<String>()
        for assignment in assignments {
            guard let entity = entitiesById[assignment.entityId],
                  let groupKey = groupKeyByEntityId[entity.entityId],
                  let group = groupsByKey[groupKey] else { continue }
            claimedGroups.insert(groupKey)
            pinned.append(KhalaDevice(
                id: "pin:\(entity.entityId)",
                name: assignment.displayLabel ?? entity.name,
                category: assignment.role,
                primaryEntityId: entity.entityId,
                stateText: KhalaText.stateText(for: entity),
                memberEntityIds: group.members.map(\.entityId),
                isPinned: true
            ))
        }

        let detected = groups
            .filter { !claimedGroups.contains($0.key) }
            .compactMap(detect)
            .sorted { lhs, rhs in
                let lhsRank = KhalaCategory.chipPriority.firstIndex(of: lhs.category) ?? Int.max
                let rhsRank = KhalaCategory.chipPriority.firstIndex(of: rhs.category) ?? Int.max
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        return pinned + detected
    }

    /// Up to `limit` devices for the Now card: everything pinned first, then the first device of each category in
    /// `KhalaCategory.chipPriority` order, then whatever is left, so the card shows variety before repetition.
    static func nowChips(from devices: [KhalaDevice], limit: Int = 3) -> [KhalaDevice] {
        var chips = Array(devices.filter(\.isPinned).prefix(limit))
        for category in KhalaCategory.chipPriority where chips.count < limit {
            guard !chips.contains(where: { $0.category == category }),
                  let device = devices.first(where: { $0.category == category && !$0.isPinned }) else { continue }
            chips.append(device)
        }
        for device in devices where chips.count < limit && !chips.contains(device) {
            chips.append(device)
        }
        return chips
    }

    /// The category of every entity that belongs to a listed device, for colouring automations by what they act on.
    static func categoryByEntityId(_ devices: [KhalaDevice]) -> [String: KhalaCategory] {
        var result: [String: KhalaCategory] = [:]
        for device in devices {
            for entityId in device.memberEntityIds where result[entityId] == nil {
                result[entityId] = device.category
            }
        }
        return result
    }

    /// Visible `camera.*` entities, by name.
    static func cameras(in entities: [KhalaEntity]) -> [KhalaEntity] {
        entities
            .filter { $0.domain == "camera" && !$0.isAuxiliary }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Grouping

    /// Entities of one registry device, or one entity on its own.
    struct Group {
        let key: String
        let members: [KhalaEntity]

        var domains: Set<String> { Set(members.map(\.domain)) }

        func first(domain: String, where predicate: (KhalaEntity) -> Bool = { _ in true }) -> KhalaEntity? {
            members
                .filter { $0.domain == domain && predicate($0) }
                .sorted { $0.entityId < $1.entityId }
                .first
        }
    }

    static func group(_ entities: [KhalaEntity]) -> [Group] {
        var order: [String] = []
        var members: [String: [KhalaEntity]] = [:]
        for entity in entities {
            let key = entity.deviceId ?? "entity:\(entity.entityId)"
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(entity)
        }
        return order.map { Group(key: $0, members: members[$0] ?? []) }
    }

    /// Domains that make a device more than "a switch": a switch on such a device is one of its features.
    private static let primaryDomains: Set<String> = [
        "media_player", "climate", "lock", "device_tracker", "camera", "water_heater",
        "vacuum", "fan", "light", "cover", "alarm_control_panel", "lawn_mower",
    ]

    private static func detect(_ group: Group) -> KhalaDevice? {
        let domains = group.domains
        let visible = group.members.filter { !$0.isAuxiliary }

        if domains.contains("device_tracker"), domains.contains("lock") || domains.contains("climate"),
           let face = group.first(domain: "sensor", where: { $0.deviceClass == "battery" && !$0.isAuxiliary })
           ?? group.first(domain: "device_tracker") {
            let tracker = group.first(domain: "device_tracker")
            return device(group, face: face, category: .car, fallbackName: tracker?.name ?? face.name)
        }
        if let heater = group.first(domain: "water_heater", where: { !$0.isAuxiliary }) {
            return device(group, face: heater, category: .heat, fallbackName: heater.name)
        }
        if domains.contains("media_player") {
            let players = visible.filter { $0.domain == "media_player" }
            let preferred = players.first { ["receiver", "tv"].contains($0.deviceClass ?? "") }
            guard let face = preferred ?? players.sorted(by: { $0.entityId < $1.entityId }).first else { return nil }
            return device(group, face: face, category: .media, fallbackName: face.name)
        }
        if domains.isDisjoint(with: primaryDomains),
           let plug = group.first(domain: "switch", where: { !$0.isAuxiliary }) {
            return device(group, face: plug, category: .neutral, fallbackName: plug.name)
        }
        return nil
    }

    private static func device(
        _ group: Group,
        face: KhalaEntity,
        category: KhalaCategory,
        fallbackName: String
    ) -> KhalaDevice {
        KhalaDevice(
            id: group.key,
            name: face.deviceName ?? fallbackName,
            category: category,
            primaryEntityId: face.entityId,
            stateText: KhalaText.stateText(for: face),
            memberEntityIds: group.members.map(\.entityId),
            isPinned: false
        )
    }
}
