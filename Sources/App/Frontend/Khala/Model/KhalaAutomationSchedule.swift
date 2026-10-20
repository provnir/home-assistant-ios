import Foundation

/// Reads an automation's raw config (the `config` of Home Assistant's `automation/config` websocket answer) and
/// works out when it will next fire, where that is knowable without running Home Assistant's engine:
/// - `time` triggers: `at` as `HH:MM[:SS]`, an `input_datetime` (time-only or date+time), a timestamp `sensor`,
///   or `{entity_id, offset}`; honours `weekday`. Templates are skipped.
/// - `sun` triggers: `sunrise`/`sunset` with an optional `offset`, from the `sun` entity's next rising/setting.
/// Conditions are not evaluated, so a time is "scheduled", not guaranteed. Both the current (`triggers` /
/// `trigger: time`) and the legacy (`trigger` / `platform: time`) spellings are accepted.
///
/// Limitation: literal times are read in `calendar`'s time zone, i.e. the phone's; Home Assistant fires them in
/// the server's zone. They only agree when phone and server share a zone.
enum KhalaAutomationSchedule {
    /// Fire dates strictly after `now` and no later than `horizon`, sorted, without duplicates.
    static func fireDates(
        config: [String: Any],
        entities: [String: KhalaEntity],
        now: Date,
        horizon: Date,
        calendar: Calendar
    ) -> [Date] {
        var dates: [Date] = []
        let triggers = KhalaValue.dictionaries(config["triggers"] ?? config["trigger"])
        for trigger in triggers where KhalaValue.bool(trigger["enabled"]) != false {
            let kind = KhalaValue.string(trigger["trigger"]) ?? KhalaValue.string(trigger["platform"])
            switch kind {
            case "time":
                dates += timeTriggerDates(trigger, entities: entities, now: now, horizon: horizon, calendar: calendar)
            case "sun":
                dates += sunTriggerDates(trigger, entities: entities)
            default:
                continue
            }
        }
        return Array(Set(dates.filter { $0 > now && $0 <= horizon })).sorted()
    }

    /// Entity ids the automation's actions name, kept only when they exist in `entities` (so service names such
    /// as `switch.turn_on`, which look like entity ids, drop out).
    static func referencedEntityIds(config: [String: Any], entities: [String: KhalaEntity]) -> [String] {
        var found: [String] = []
        collect(config["actions"] ?? config["action"], into: &found)
        var seen = Set<String>()
        return found.filter { entities[$0] != nil && seen.insert($0).inserted }
    }

    // MARK: - Time triggers

    private static func timeTriggerDates(
        _ trigger: [String: Any],
        entities: [String: KhalaEntity],
        now: Date,
        horizon: Date,
        calendar: Calendar
    ) -> [Date] {
        let weekdays = Set(KhalaValue.list(trigger["weekday"]).compactMap { ($0 as? String).flatMap(weekdayNumber) })
        var dates: [Date] = []
        for at in KhalaValue.list(trigger["at"]) {
            if let string = at as? String {
                if let seconds = KhalaDateParser.timeOfDay(string) {
                    dates += daily(secondsOfDay: seconds, now: now, horizon: horizon, calendar: calendar)
                } else if let entity = entities[string] {
                    dates += entityDates(entity, offset: 0, now: now, horizon: horizon, calendar: calendar)
                }
            } else if let dictionary = at as? [String: Any],
                      let entityId = KhalaValue.string(dictionary["entity_id"]),
                      let entity = entities[entityId] {
                let offset = KhalaDateParser.duration(dictionary["offset"]) ?? 0
                dates += entityDates(entity, offset: offset, now: now, horizon: horizon, calendar: calendar)
            }
        }
        guard !weekdays.isEmpty else { return dates }
        return dates.filter { weekdays.contains(calendar.component(.weekday, from: $0)) }
    }

    private static func entityDates(
        _ entity: KhalaEntity,
        offset: TimeInterval,
        now: Date,
        horizon: Date,
        calendar: Calendar
    ) -> [Date] {
        if let seconds = entity.timeOfDay {
            return daily(secondsOfDay: seconds, now: now, horizon: horizon, calendar: calendar)
                .map { $0.addingTimeInterval(offset) }
        }
        if let date = entity.stateDate {
            return [date.addingTimeInterval(offset)]
        }
        return []
    }

    /// The occurrences of a local time of day from the start of today until `horizon`.
    private static func daily(secondsOfDay: Int, now: Date, horizon: Date, calendar: Calendar) -> [Date] {
        let startOfToday = calendar.startOfDay(for: now)
        var dates: [Date] = []
        var dayOffset = 0
        while dayOffset < 8 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { break }
            let hour = secondsOfDay / 3600
            let minute = (secondsOfDay % 3600) / 60
            let second = secondsOfDay % 60
            if let date = calendar.date(bySettingHour: hour, minute: minute, second: second, of: day) {
                if date > horizon { break }
                dates.append(date)
            }
            dayOffset += 1
        }
        return dates
    }

    /// HA's `weekday` values (`mon` ... `sun`) as `Calendar` weekday numbers (Sunday = 1).
    private static func weekdayNumber(_ name: String) -> Int? {
        ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7][name.lowercased()]
    }

    // MARK: - Sun triggers

    private static func sunTriggerDates(_ trigger: [String: Any], entities: [String: KhalaEntity]) -> [Date] {
        guard let sun = entities.values.first(where: { $0.domain == "sun" }) else { return [] }
        let offset = KhalaDateParser.duration(trigger["offset"]) ?? 0
        let next: Date?
        switch KhalaValue.string(trigger["event"]) {
        case "sunrise": next = sun.nextRising
        case "sunset": next = sun.nextSetting
        default: next = nil
        }
        guard let next else { return [] }
        // The previous occurrence is about a day earlier; with a positive offset it can still be ahead of us.
        return [next.addingTimeInterval(offset), next.addingTimeInterval(offset - 86400)]
    }

    // MARK: - Entity references

    private static func collect(_ value: Any?, into found: inout [String]) {
        switch value {
        case let string as String:
            for part in string.split(separator: ",") {
                let candidate = part.trimmingCharacters(in: .whitespaces)
                if looksLikeEntityId(candidate) { found.append(candidate) }
            }
        case let array as [Any]:
            for element in array {
                collect(element, into: &found)
            }
        case let dictionary as [String: Any]:
            for key in dictionary.keys.sorted() {
                collect(dictionary[key], into: &found)
            }
        default:
            break
        }
    }

    private static func looksLikeEntityId(_ string: String) -> Bool {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        return string.allSatisfy { $0 == "." || $0 == "_" || $0.isNumber || ($0.isLetter && $0.isLowercase) }
    }
}
