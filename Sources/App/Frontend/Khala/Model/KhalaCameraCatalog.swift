import Foundation

/// Everything Khala's camera screens read about a camera, from entity states and recorder history: its event
/// entities (detections), the rows of the picker and grid, today's detections, and the optional controls.
/// Event entities belong to a camera when they share its registry device, or — without registry data — when the
/// camera's name starts theirs.
enum KhalaCameraCatalog {
    /// `event.*` entities of the camera's device, motion/doorbell kinds first.
    static func eventEntities(for camera: KhalaEntity, in entities: [KhalaEntity]) -> [KhalaEntity] {
        entities
            .filter { $0.domain == "event" && !$0.isAuxiliary }
            .filter { event in
                if let deviceId = camera.deviceId {
                    return event.deviceId == deviceId
                }
                return event.name.hasPrefix(camera.name + " ")
            }
            .sorted { lhs, rhs in
                let lhsRank = isDetectionClass(lhs.deviceClass) ? 0 : 1
                let rhsRank = isDetectionClass(rhs.deviceClass) ? 0 : 1
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.entityId < rhs.entityId
            }
    }

    /// The detections of a camera between `since` and `now`, newest first: the current state of each of its
    /// event entities plus whatever `history` holds for them, without duplicates.
    static func detections(
        for camera: KhalaEntity,
        in entities: [KhalaEntity],
        history: [String: [KhalaHistoryState]] = [:],
        since: Date,
        now: Date
    ) -> [KhalaDetection] {
        var seen = Set<String>()
        var result: [KhalaDetection] = []
        for event in eventEntities(for: camera, in: entities) where isDetectionClass(event.deviceClass) {
            let source = sourceName(event, camera: camera)
            var candidates: [(Date, String?)] = []
            if let date = event.stateDate { candidates.append((date, event.eventType)) }
            for item in history[event.entityId] ?? [] {
                // An event entity's state is the time of its last event.
                if let date = KhalaDateParser.timestamp(item.state) { candidates.append((date, item.eventType)) }
            }
            for (date, type) in candidates where date >= since && date <= now {
                let detection = KhalaDetection(
                    eventEntityId: event.entityId,
                    date: date,
                    noun: KhalaText.detectionNoun(eventType: type, deviceClass: event.deviceClass),
                    source: source
                )
                if seen.insert(detection.id).inserted { result.append(detection) }
            }
        }
        return result.sorted { $0.date > $1.date }
    }

    /// The picker / grid rows for `cameras`, in the given order.
    static func rows(
        cameras: [KhalaEntity],
        entities: [KhalaEntity],
        now: Date,
        calendar: Calendar
    ) -> [KhalaCameraRow] {
        let startOfToday = calendar.startOfDay(for: now)
        return cameras.map { camera in
            let latest = detections(for: camera, in: entities, since: startOfToday, now: now).first
            let stateText: String
            if camera.isUnavailable {
                stateText = KhalaText.humanized(state: camera.state)
            } else if let latest {
                stateText = "\(latest.noun) \(KhalaText.time(latest.date, calendar: calendar))"
            } else {
                stateText = KhalaScreenText.clear
            }
            return KhalaCameraRow(
                entityId: camera.entityId,
                name: camera.name,
                stateText: stateText,
                hasDetectionToday: latest != nil,
                isUnavailable: camera.isUnavailable
            )
        }
    }

    /// A switch on the camera's device that controls its notifications/alerts (e.g. a "Push notifications"
    /// switch), which the Mute action turns off. Nil when the camera has none: the action is then hidden.
    static func notificationSwitch(for camera: KhalaEntity, in entities: [KhalaEntity]) -> KhalaEntity? {
        guard let deviceId = camera.deviceId else { return nil }
        return entities
            .filter { $0.domain == "switch" && $0.deviceId == deviceId }
            .filter { entity in
                let text = (entity.entityId + " " + entity.name).lowercased()
                return ["notif", "push", "alert"].contains { text.contains($0) }
            }
            .sorted { $0.entityId < $1.entityId }
            .first
    }

    /// Whether the camera reports the `stream` feature (`CameraEntityFeature.STREAM` = 2), i.e. a live stream
    /// rather than stills only.
    static func supportsStream(attributes: [String: Any]) -> Bool {
        (KhalaValue.int(attributes["supported_features"]) ?? 0) & 2 != 0
    }

    /// The line under the camera's title: "3 detections today" or "All clear today".
    static func subtitle(detectionsToday: Int) -> String {
        detectionsToday == 0 ? KhalaScreenText.clearToday : KhalaText.detections(detectionsToday)
    }

    // MARK: - Private

    private static func isDetectionClass(_ deviceClass: String?) -> Bool {
        deviceClass == "motion" || deviceClass == "doorbell"
    }

    /// An event entity's name without its camera's ("Field detection").
    static func sourceName(_ event: KhalaEntity, camera: KhalaEntity) -> String {
        if event.deviceName != nil { return event.nameWithoutDevice }
        guard event.name.hasPrefix(camera.name + " ") else { return event.name }
        return String(event.name.dropFirst(camera.name.count + 1))
    }
}
