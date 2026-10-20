import Foundation

/// A plain, Foundation-only snapshot of one Home Assistant entity: the subset of its state and attributes Khala
/// reads, already typed. Built from HAKit's `HAEntity` by `KhalaHomeViewModel` (plus registry facts from the app
/// database) and from raw JSON in tests, so the timeline and device logic never touch HAKit or UIKit.
struct KhalaEntity: Equatable {
    let entityId: String
    let domain: String
    let state: String
    /// `friendly_name`, falling back to the entity id.
    let name: String
    let deviceClass: String?
    let unit: String?
    let lastChanged: Date

    /// Registry device the entity belongs to, if any.
    let deviceId: String?
    /// The device's display name (user's name first), if known.
    let deviceName: String?
    /// Config/diagnostic or hidden in the entity registry: never a device's face or a timeline item.
    let isAuxiliary: Bool

    /// The state read as a timestamp (`event.*`, `sensor` with device class `timestamp`, `image.*`).
    let stateDate: Date?
    /// `event.*`: the type of the last event (`human`, `vehicle`, `ring`, ...).
    let eventType: String?
    /// `sun.*`: next sunrise / sunset.
    let nextRising: Date?
    let nextSetting: Date?
    /// `weather.*` `temperature`, or `current_temperature` for water heaters and climate entities.
    let temperature: Double?
    /// `input_datetime.*` with a time but no date: seconds after midnight.
    let timeOfDay: Int?

    init(
        entityId: String,
        state: String,
        lastChanged: Date,
        attributes: [String: Any],
        deviceId: String? = nil,
        deviceName: String? = nil,
        isAuxiliary: Bool = false
    ) {
        self.entityId = entityId
        let domain = entityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? entityId
        self.domain = domain
        self.state = state
        self.name = KhalaValue.string(attributes["friendly_name"]) ?? entityId
        self.deviceClass = KhalaValue.string(attributes["device_class"])
        self.unit = KhalaValue.string(attributes["unit_of_measurement"])
        self.lastChanged = lastChanged
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.isAuxiliary = isAuxiliary

        self.stateDate = Self.stateDate(domain: domain, state: state, attributes: attributes)
        self.eventType = domain == "event" ? KhalaValue.string(attributes["event_type"]) : nil
        self.nextRising = KhalaValue.string(attributes["next_rising"]).flatMap(KhalaDateParser.timestamp)
        self.nextSetting = KhalaValue.string(attributes["next_setting"]).flatMap(KhalaDateParser.timestamp)
        self.temperature = domain == "weather"
            ? KhalaValue.double(attributes["temperature"])
            : KhalaValue.double(attributes["current_temperature"])

        if domain == "input_datetime",
           KhalaValue.bool(attributes["has_time"]) == true,
           KhalaValue.bool(attributes["has_date"]) != true {
            let hour = KhalaValue.int(attributes["hour"]) ?? 0
            let minute = KhalaValue.int(attributes["minute"]) ?? 0
            let second = KhalaValue.int(attributes["second"]) ?? 0
            self.timeOfDay = hour * 3600 + minute * 60 + second
        } else {
            self.timeOfDay = nil
        }
    }

    /// The friendly name with the device name taken off its front, e.g.
    /// "Porch Field detection" on device "Porch" → "Field detection". The whole name when there's nothing to strip.
    var nameWithoutDevice: String {
        guard let deviceName, name.count > deviceName.count, name.hasPrefix(deviceName) else { return name }
        let rest = name.dropFirst(deviceName.count).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? name : rest
    }

    /// Whether Home Assistant reports no usable state.
    var isUnavailable: Bool {
        state == "unavailable" || state == "unknown"
    }

    private static func stateDate(domain: String, state: String, attributes: [String: Any]) -> Date? {
        if domain == "input_datetime" {
            // Date + time helpers carry a local epoch in `timestamp`; time-only ones use `timeOfDay` instead.
            guard KhalaValue.bool(attributes["has_date"]) == true,
                  KhalaValue.bool(attributes["has_time"]) == true,
                  let seconds = KhalaValue.double(attributes["timestamp"]) else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        return KhalaDateParser.timestamp(state)
    }
}
