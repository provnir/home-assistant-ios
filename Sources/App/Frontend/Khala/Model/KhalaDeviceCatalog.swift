import Foundation

/// Turns entity states into the devices Khala lists, without knowing any particular home: roles come from Home
/// Assistant data (domains present on a registry device, device classes) and from the user's role assignments.
///
/// Detection, per registry device (an entity without a device stands alone):
/// Each detected device gets the `KhalaKind` its rule stands for (car, water heater, media, switch) and that kind's
/// accent; a pin gets the assignment's kind and role colour.
/// - **car**: has a `device_tracker` and a `lock` or `climate` (phones have trackers but no locks); shows the
///   battery sensor when there is one, else where the tracker is.
/// - **heat**: has a `water_heater`.
/// - **media**: has a `media_player` (receivers and TVs preferred as the face).
/// - **climate, lock, cover, fan, light group, light, switch** (slices 3–4, through `KhalaDescriptors`): a device
///   with none of the domains detection doesn't cover yet (vacuum, camera, alarm panel…) takes the kind of its best
///   member — climate 80, lock 55, cover 50, fan 45, light group 41, light 40, switch 10 — ties to the entity with
///   no `translation_key`, then the lowest id. So a garage opener with a light is a cover whose light is one of its
///   controls, and an air conditioner with a display switch is a climate. Only `switch` entities make a switch
///   (helpers such as `input_boolean` stay off the menu, as in 41.1).
///   A light that is a member of a listed light group is folded into the group's screen, not listed again.
/// - **labels** (decision 2): an entity labelled `khala:hide` is left out of detection entirely; a
///   `khala:kind:<kind>` label makes its device that kind, before every rule above.
/// Cameras are not listed (the menu counts them under Cameras). Pinned assignments come first, in the user's
/// order, and take over the whole device they belong to; a pin beats every label. Detected devices follow by colour
/// family (`KhalaCategory.chipPriority`), then kind priority (a water heater before an air conditioner, a light
/// group before its lights), then name.
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
                kind: assignment.kind,
                accent: assignment.role,
                primaryEntityId: entity.entityId,
                stateText: KhalaText.stateText(for: entity),
                memberEntityIds: group.members.map(\.entityId),
                isPinned: true,
                areaId: entity.areaId,
                glyph: KhalaIconChain.device(kind: assignment.kind, face: entity)
            ))
        }

        let candidates = groups
            .filter { !claimedGroups.contains($0.key) }
            .compactMap { group -> KhalaDevice? in
                let shown = group.members.filter { !KhalaLabelOverride.isHidden($0) }
                guard !shown.isEmpty else { return nil }
                return detect(Group(key: group.key, members: shown))
            }
        // Lights already reachable through a listed group's members are not listed again.
        let listed = pinned + candidates
        let folded = Set(listed.flatMap { device -> [String] in
            guard let face = entitiesById[device.primaryEntityId],
                  face.domain == "light" || device.kind == .lightGroup else { return [] }
            return face.groupMembers
        })
        let detected = candidates
            .filter { !(($0.kind == .light) && folded.contains($0.primaryEntityId)) }
            .sorted { lhs, rhs in
                let lhsRank = KhalaCategory.chipPriority.firstIndex(of: lhs.category) ?? Int.max
                let rhsRank = KhalaCategory.chipPriority.firstIndex(of: rhs.category) ?? Int.max
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                let lhsPriority = lhs.kind.descriptor.priority
                let rhsPriority = rhs.kind.descriptor.priority
                if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
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
            .filter { $0.domain == "camera" && !$0.isAuxiliary && !KhalaLabelOverride.isHidden($0) }
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

    /// Domains of devices detection doesn't cover yet (slice 6) or covers by its own rule (car, heater, media):
    /// a light, switch, cover, lock or climate on such a device is one of its features, not its face.
    private static let deferredDomains: Set<String> = [
        "media_player", "device_tracker", "camera", "water_heater", "vacuum", "alarm_control_panel", "lawn_mower",
    ]

    /// The kinds detected through descriptors (slice 3: fans, lights, switches; slice 4: climate, locks, covers).
    static let descriptorKinds: Set<KhalaKind> = [.climate, .lock, .cover, .fan, .lightGroup, .light, .switch]

    private static func detect(_ group: Group) -> KhalaDevice? {
        let domains = group.domains
        let visible = group.members.filter { !$0.isAuxiliary }

        // A `khala:kind:<kind>` label beats the built-in rules.
        let labelled = visible.compactMap { entity in KhalaLabelOverride.kind(of: entity).map { (entity, $0) } }
        if let (face, kind) = best(labelled) {
            return device(group, face: face, kind: kind, fallbackName: face.name)
        }

        if domains.contains("device_tracker"), domains.contains("lock") || domains.contains("climate"),
           let face = group.first(domain: "sensor", where: { $0.deviceClass == "battery" && !$0.isAuxiliary })
           ?? group.first(domain: "device_tracker") {
            let tracker = group.first(domain: "device_tracker")
            return device(group, face: face, kind: .car, fallbackName: tracker?.name ?? face.name)
        }
        if let heater = group.first(domain: "water_heater", where: { !$0.isAuxiliary }) {
            return device(group, face: heater, kind: .waterHeater, fallbackName: heater.name)
        }
        if domains.contains("media_player") {
            let players = visible.filter { $0.domain == "media_player" }
            let preferred = players.first { ["receiver", "tv"].contains($0.deviceClass ?? "") }
            guard let face = preferred ?? players.sorted(by: { $0.entityId < $1.entityId }).first else { return nil }
            return device(group, face: face, kind: .media, fallbackName: face.name)
        }
        if domains.isDisjoint(with: deferredDomains) {
            let faces = visible.compactMap { entity -> (KhalaEntity, KhalaKind)? in
                let kind = KhalaDescriptors.shown(for: entity).kind
                guard descriptorKinds.contains(kind), kind != .switch || entity.domain == "switch" else { return nil }
                return (entity, kind)
            }
            if let (face, kind) = best(faces) {
                return device(group, face: face, kind: kind, fallbackName: face.name)
            }
        }
        return nil
    }

    /// The face among candidate (entity, kind) pairs: the highest kind priority, then the device's main entity (no
    /// `translation_key`), then the lowest entity id.
    private static func best(_ candidates: [(KhalaEntity, KhalaKind)]) -> (KhalaEntity, KhalaKind)? {
        candidates.min { lhs, rhs in
            let lhsPriority = lhs.1.descriptor.priority
            let rhsPriority = rhs.1.descriptor.priority
            if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
            let lhsMain = lhs.0.translationKey == nil
            let rhsMain = rhs.0.translationKey == nil
            if lhsMain != rhsMain { return lhsMain }
            return lhs.0.entityId < rhs.0.entityId
        }
    }

    private static func device(
        _ group: Group,
        face: KhalaEntity,
        kind: KhalaKind,
        fallbackName: String
    ) -> KhalaDevice {
        KhalaDevice(
            id: group.key,
            name: face.deviceName ?? fallbackName,
            kind: kind,
            primaryEntityId: face.entityId,
            stateText: KhalaText.stateText(for: face),
            memberEntityIds: group.members.map(\.entityId),
            isPinned: false,
            areaId: face.areaId,
            glyph: KhalaIconChain.device(kind: kind, face: face)
        )
    }
}
