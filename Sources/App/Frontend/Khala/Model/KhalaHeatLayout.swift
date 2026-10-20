import Foundation

/// The hot-water screen (mockup `DayWater`) for a device with the heat role: a `water_heater`, or a plain switch the
/// user pinned as hot water. Reads the heater's state, a remaining-time sensor when the device has one, and decides
/// the "Heat now" action:
/// - a Switcher (`switcher_kis` platform) gets `switcher_kis.turn_on_with_timer` with the chosen minutes;
/// - any other switch gets `switch.turn_on` (no timer; the duration control is hidden);
/// - a `water_heater` gets `water_heater.turn_on`.
struct KhalaHeatLayout: Equatable {
    /// The durations the segmented control offers, in minutes (a fixed small set, DESIGN.md).
    static let durations = [30, 45, 60, 90]
    static let defaultDuration = 45

    let heaterEntityId: String
    let isOn: Bool
    let isUnavailable: Bool
    /// "On", "Off", "52°".
    let stateText: String
    /// Seconds left on the device's own timer, when it reports one.
    let remaining: TimeInterval?
    /// "2.4 kW" while drawing power.
    let powerText: String?
    let supportsDuration: Bool

    /// `platform` is the heater entity's integration from the entity registry (nil when unknown).
    init(heater: KhalaEntity, platform: String?, members: [KhalaEntity]) {
        heaterEntityId = heater.entityId
        isUnavailable = heater.isUnavailable
        isOn = !["off", "unavailable", "unknown"].contains(heater.state)
        if heater.domain == "water_heater", let temperature = heater.temperature {
            stateText = "\(Int(temperature.rounded()))°"
        } else {
            stateText = KhalaText.humanized(state: heater.state)
        }
        supportsDuration = platform == "switcher_kis" && heater.domain == "switch"

        func text(_ entity: KhalaEntity) -> String { (entity.entityId + " " + entity.name).lowercased() }
        let sensors = members.filter { $0.domain == "sensor" && !$0.isUnavailable }
        let remainingSensor = sensors.first { sensor in
            ["remaining", "time_left", "time left"].contains { text(sensor).contains($0) }
        }
        remaining = remainingSensor.flatMap { Self.seconds($0.state, unit: $0.unit) }
        if let power = sensors.first(where: { $0.deviceClass == "power" }), let watts = Double(power.state), watts > 0 {
            powerText = KhalaText.measurement(power.unit == "W" && watts >= 1000 ? watts / 1000 : watts,
                                              unit: power.unit == "W" && watts >= 1000 ? "kW" : power.unit)
        } else {
            powerText = nil
        }
    }

    func heatCall(minutes: Int) -> KhalaServiceCall {
        if supportsDuration {
            return KhalaServiceCall("switcher_kis", "turn_on_with_timer", entityId: heaterEntityId,
                                    data: ["timer_minutes": minutes])
        }
        return KhalaServiceCall.power(heaterEntityId, on: true)
    }

    var offCall: KhalaServiceCall {
        KhalaServiceCall.power(heaterEntityId, on: false)
    }

    /// A remaining-time state in seconds: "00:32:10", "32:10", or a number in the sensor's unit (min/s/h).
    static func seconds(_ state: String, unit: String?) -> TimeInterval? {
        let parts = state.split(separator: ":").map { Int($0) }
        if parts.count >= 2, parts.allSatisfy({ $0 != nil }) {
            let numbers = parts.compactMap { $0 }
            return TimeInterval(numbers.count == 3
                ? numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
                : numbers[0] * 60 + numbers[1])
        }
        guard let value = Double(state) else { return nil }
        switch unit {
        case "s": return value
        case "h": return value * 3600
        case "d": return value * 86400
        default: return value * 60
        }
    }
}
