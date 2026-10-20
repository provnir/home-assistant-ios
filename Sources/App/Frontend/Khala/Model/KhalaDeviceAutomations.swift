import Foundation

/// Finds the automations that run a device on a clock, from their configs (`automation/config`):
/// - **targeting**: an action names one of the device's entities, and a trigger is a time or sun trigger;
/// - **linked**: a time-triggered automation that shares a helper (`input_*`, `timer`) with a targeting one — e.g.
///   a midnight check that books a morning run through an `input_boolean` the morning automation reads.
/// Disabled automations are included (with `isEnabled` false) so they can be switched back on.
enum KhalaDeviceAutomations {
    static let helperDomains: Set<String> = [
        "input_boolean", "input_datetime", "input_number", "input_select", "input_text", "input_button", "timer",
    ]

    static func related(
        to deviceEntityIds: Set<String>,
        configs: [String: [String: Any]],
        entities: [KhalaEntity],
        now: Date,
        horizon: TimeInterval,
        calendar: Calendar
    ) -> [KhalaDeviceAutomation] {
        let byId = Dictionary(entities.map { ($0.entityId, $0) }, uniquingKeysWith: { first, _ in first })
        var targeting: [String] = []
        var helpers = Set<String>()
        var referencesById: [String: [String]] = [:]
        for (automationId, config) in configs {
            let actionRefs = KhalaAutomationSchedule.referencedEntityIds(config: config, entities: byId)
            let allRefs = KhalaAutomationSchedule.referencedEntityIds(
                config: ["actions": [
                    config["actions"] ?? config["action"] ?? [Any](),
                    config["conditions"] ?? config["condition"] ?? [Any](),
                ]],
                entities: byId
            )
            referencesById[automationId] = allRefs
            if actionRefs.contains(where: deviceEntityIds.contains) {
                targeting.append(automationId)
                helpers.formUnion(allRefs.filter { helperDomains.contains(domain($0)) })
            }
        }
        var result: [KhalaDeviceAutomation] = []
        for (automationId, config) in configs {
            let isTargeting = targeting.contains(automationId)
            let isLinked = !isTargeting && (referencesById[automationId] ?? []).contains(where: helpers.contains)
            guard isTargeting || isLinked else { continue }
            let times = timesOfDay(config)
            let dates = KhalaAutomationSchedule.fireDates(
                config: config,
                entities: byId,
                now: now,
                horizon: now.addingTimeInterval(horizon),
                calendar: calendar
            )
            guard !dates.isEmpty || !times.isEmpty else { continue }
            let entity = byId[automationId]
            result.append(KhalaDeviceAutomation(
                automationId: automationId,
                name: entity?.name ?? KhalaValue.string(config["alias"]) ?? automationId,
                description: KhalaValue.string(config["description"]),
                isEnabled: entity?.state == "on",
                fireDates: dates,
                timesOfDay: times,
                runMinutes: isTargeting ? runMinutes(config, deviceEntityIds: deviceEntityIds) : nil,
                targetsDevice: isTargeting
            ))
        }
        return result.sorted { lhs, rhs in
            switch (lhs.fireDates.first, rhs.fireDates.first) {
            case let (left?, right?) where left != right: return left < right
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    /// Literal `at: "HH:MM[:SS]"` times of the automation's enabled time triggers.
    static func timesOfDay(_ config: [String: Any]) -> [Int] {
        var times: [Int] = []
        for trigger in KhalaValue.dictionaries(config["triggers"] ?? config["trigger"])
            where KhalaValue.bool(trigger["enabled"]) != false {
            let kind = KhalaValue.string(trigger["trigger"]) ?? KhalaValue.string(trigger["platform"])
            guard kind == "time" else { continue }
            for at in KhalaValue.list(trigger["at"]) {
                if let string = at as? String, let seconds = KhalaDateParser.timeOfDay(string) {
                    times.append(seconds)
                }
            }
        }
        return Array(Set(times)).sorted()
    }

    /// The run length an action gives the device: `timer_minutes` (Switcher) or a `duration`, in minutes.
    static func runMinutes(_ config: [String: Any], deviceEntityIds: Set<String>) -> Int? {
        var found: Int?
        visitActions(config["actions"] ?? config["action"]) { action in
            guard found == nil else { return }
            var refs: [String] = []
            for key in ["target", "entity_id", "data"] {
                refs += KhalaValue.list(action[key]).compactMap { $0 as? String }
                if let target = action[key] as? [String: Any] {
                    refs += KhalaValue.list(target["entity_id"]).compactMap { $0 as? String }
                }
            }
            guard refs.contains(where: deviceEntityIds.contains) else { return }
            let data = (action["data"] as? [String: Any]) ?? (action["service_data"] as? [String: Any]) ?? [:]
            if let minutes = KhalaValue.int(data["timer_minutes"]) {
                found = minutes
            } else if let seconds = KhalaDateParser.duration(data["duration"]) {
                found = Int((seconds / 60).rounded())
            }
        }
        return found
    }

    // MARK: - Private

    private static func domain(_ entityId: String) -> String {
        entityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? entityId
    }

    /// Walks every action dictionary, including those nested in `if/then/else`, `choose`, `sequence`, `parallel`.
    private static func visitActions(_ value: Any?, _ visit: ([String: Any]) -> Void) {
        for action in KhalaValue.dictionaries(value) {
            visit(action)
            for key in ["then", "else", "sequence", "parallel", "default"] {
                visitActions(action[key], visit)
            }
            for option in KhalaValue.dictionaries(action["choose"]) {
                visitActions(option["sequence"], visit)
            }
        }
    }
}
