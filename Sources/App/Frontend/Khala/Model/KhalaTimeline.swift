import Foundation

/// The Today screen's content: the home's day as one ordered list — what already happened above "Now", what is
/// coming below — plus the Now card's headline and chips. Pure function of entity states, so it can be built and
/// tested anywhere Foundation runs.
///
/// Sources, all read from live states (nothing home-specific is named in code):
/// - sunrise/sunset from the `sun` entity (`next_rising`/`next_setting`; the one already behind us today is
///   estimated as the next one minus a day, which is off by the day-length change, ~2 minutes at most);
/// - today's detections from `event.*` entities with device class `motion` or `doorbell` (an event entity only
///   holds its LAST event, so each one contributes at most one row — history would need the recorder);
/// - enabled automations' next time/sun triggers (`KhalaAutomationSchedule`), when their configs were fetched;
/// - `sensor`s with device class `timestamp` of a listed device, pointing later today.
struct KhalaTimeline: Equatable {
    var items: [KhalaTimelineItem]
    /// The Now card's line: "21° and sunny · sunset in 5 h 32 m".
    var headline: String
    /// The line under the title: "all clear" or "3 detections today".
    var summary: String
    /// Up to three devices for the Now card.
    var chips: [KhalaDevice]

    static let empty = KhalaTimeline(items: [], headline: KhalaText.rightNow, summary: KhalaText.allClear, chips: [])

    /// How far past midnight upcoming items reach, so a midnight automation still shows tonight.
    static let upcomingGrace: TimeInterval = 3600
    static let maximumDetections = 8
    static let maximumUpcoming = 8

    static func build(
        entities: [KhalaEntity],
        devices: [KhalaDevice],
        automationConfigs: [String: [String: Any]],
        now: Date,
        calendar: Calendar
    ) -> KhalaTimeline {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? startOfToday.addingTimeInterval(86400)
        let horizon = startOfTomorrow.addingTimeInterval(upcomingGrace)
        let entitiesById = Dictionary(entities.map { ($0.entityId, $0) }, uniquingKeysWith: { first, _ in first })
        let categories = KhalaDeviceCatalog.categoryByEntityId(devices)
        let deviceNameByEntityId = devices.reduce(into: [String: String]()) { result, device in
            for entityId in device.memberEntityIds where result[entityId] == nil {
                result[entityId] = device.name
            }
        }

        let sun = entities.first { $0.domain == "sun" }
        let sunItems = sun.map { sunEvents($0, now: now, horizon: horizon, calendar: calendar) } ?? []

        let allDetections = detections(entities, now: now, startOfToday: startOfToday)
        let shownDetections = Array(allDetections.sorted { $0.date > $1.date }.prefix(maximumDetections))

        var upcoming: [KhalaTimelineItem] = []
        for (automationId, config) in automationConfigs {
            guard let automation = entitiesById[automationId], automation.state == "on" else { continue }
            let dates = KhalaAutomationSchedule.fireDates(
                config: config,
                entities: entitiesById,
                now: now,
                horizon: horizon,
                calendar: calendar
            )
            guard !dates.isEmpty else { continue }
            let targets = KhalaAutomationSchedule.referencedEntityIds(config: config, entities: entitiesById)
            let category = targets.lazy.compactMap { categories[$0] }.first ?? .neutral
            let targetName = targets.lazy.compactMap { deviceNameByEntityId[$0] }.first
            for date in dates {
                upcoming.append(KhalaTimelineItem(
                    id: "scheduled:\(automationId):\(Int(date.timeIntervalSince1970))",
                    date: date,
                    kind: .scheduled(automationEntityId: automationId),
                    title: automation.name,
                    subtitle: targetName.map { "\(KhalaText.automation) · \($0)" } ?? KhalaText.automation,
                    category: category,
                    isPast: false,
                    targetEntityId: automationId
                ))
            }
        }
        // Only the timestamp sensors of devices Khala lists (a car's "charged at"), not every integration's
        // bookkeeping (the sun's own next-dusk sensors, backup schedules, ...).
        for entity in entities where entity.domain == "sensor" && entity.deviceClass == "timestamp" {
            guard !entity.isAuxiliary, categories[entity.entityId] != nil,
                  let date = entity.stateDate, date > now, date <= horizon else { continue }
            upcoming.append(KhalaTimelineItem(
                id: "timestamp:\(entity.entityId)",
                date: date,
                kind: .timestamp(entityId: entity.entityId),
                title: entity.name,
                subtitle: entity.deviceName,
                category: categories[entity.entityId] ?? .neutral,
                isPast: false,
                targetEntityId: entity.entityId
            ))
        }
        upcoming = Array(upcoming.sorted { $0.date < $1.date }.prefix(maximumUpcoming))

        let nowItem = KhalaTimelineItem(
            id: "now",
            date: now,
            kind: .now,
            title: KhalaText.now,
            subtitle: nil,
            category: .neutral,
            isPast: false,
            targetEntityId: nil
        )

        let items = (sunItems + shownDetections + upcoming + [nowItem]).sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return order(lhs) < order(rhs)
        }

        return KhalaTimeline(
            items: items,
            headline: headline(entities: entities, sun: sun, now: now),
            summary: allDetections.isEmpty ? KhalaText.allClear : KhalaText.detections(allDetections.count),
            chips: KhalaDeviceCatalog.nowChips(from: devices)
        )
    }

    // MARK: - Pieces

    private static func sunEvents(
        _ sun: KhalaEntity,
        now: Date,
        horizon: Date,
        calendar: Calendar
    ) -> [KhalaTimelineItem] {
        var items: [KhalaTimelineItem] = []
        let events: [(Date?, KhalaTimelineItem.Kind, String)] = [
            (sun.nextRising, .sunrise, KhalaText.sunrise),
            (sun.nextSetting, .sunset, KhalaText.sunset),
        ]
        for (next, kind, title) in events {
            guard let next else { continue }
            // Today's occurrence: the next one when it is still today, else the one before it.
            let candidates = [next, next.addingTimeInterval(-86400)]
            guard let date = candidates.first(where: { calendar.isDate($0, inSameDayAs: now) }) else { continue }
            guard date <= horizon else { continue }
            items.append(KhalaTimelineItem(
                id: "sun:\(title)",
                date: date,
                kind: kind,
                title: title,
                subtitle: nil,
                category: .sun,
                isPast: date <= now,
                targetEntityId: nil
            ))
        }
        return items
    }

    private static func detections(_ entities: [KhalaEntity], now: Date, startOfToday: Date) -> [KhalaTimelineItem] {
        let camerasByDevice = entities.reduce(into: [String: KhalaEntity]()) { result, entity in
            guard entity.domain == "camera", let deviceId = entity.deviceId, result[deviceId] == nil else { return }
            result[deviceId] = entity
        }
        return entities.compactMap { entity in
            guard entity.domain == "event",
                  entity.deviceClass == "motion" || entity.deviceClass == "doorbell",
                  !entity.isAuxiliary,
                  let date = entity.stateDate, date >= startOfToday, date <= now else { return nil }
            let camera = entity.deviceId.flatMap { camerasByDevice[$0] }
            let place = entity.deviceName ?? camera?.name ?? entity.name
            let noun = KhalaText.detectionNoun(eventType: entity.eventType, deviceClass: entity.deviceClass)
            // "Field detection": the event's own name, once the device name is in the title.
            let subtitle = entity.deviceName == nil ? nil : entity.nameWithoutDevice
            return KhalaTimelineItem(
                id: "detection:\(entity.entityId)",
                date: date,
                kind: .detection(eventEntityId: entity.entityId, cameraEntityId: camera?.entityId),
                title: "\(noun) at \(place)",
                subtitle: subtitle,
                category: .security,
                isPast: true,
                targetEntityId: camera?.entityId ?? entity.entityId
            )
        }
    }

    private static func headline(entities: [KhalaEntity], sun: KhalaEntity?, now: Date) -> String {
        var parts: [String] = []
        if let weather = entities.first(where: { $0.domain == "weather" && !$0.isUnavailable }) {
            let condition = KhalaText.weatherCondition(weather.state)
            if let temperature = weather.temperature {
                parts.append("\(Int(temperature.rounded()))° and \(condition)")
            } else {
                parts.append(condition.prefix(1).uppercased() + condition.dropFirst())
            }
        }
        if let sun {
            if let setting = sun.nextSetting, setting > now, setting.timeIntervalSince(now) < 18 * 3600,
               sun.nextRising.map({ setting < $0 }) ?? true {
                parts.append("sunset in \(KhalaText.duration(setting.timeIntervalSince(now)))")
            } else if let rising = sun.nextRising, rising > now, rising.timeIntervalSince(now) < 18 * 3600 {
                parts.append("sunrise in \(KhalaText.duration(rising.timeIntervalSince(now)))")
            }
        }
        guard !parts.isEmpty else { return KhalaText.rightNow }
        let line = parts.joined(separator: " · ")
        return line.prefix(1).uppercased() + line.dropFirst()
    }

    /// Tie-break for items at the same minute: what happened, then now, then what's next.
    private static func order(_ item: KhalaTimelineItem) -> Int {
        if item.isPast { return 0 }
        return item.isNow ? 1 : 2
    }
}
