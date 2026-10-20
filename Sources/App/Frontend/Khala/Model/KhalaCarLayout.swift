import Foundation

/// A car's screens (mockup `DayCar`) read from the entities of its Home Assistant device — whatever the
/// integration exposes, nothing assumed: tiles exist only for entities that exist.
///
/// Sorting, by domain, device class and the words integrations use in entity ids/names (types are code, which
/// car is which is data):
/// - **Overview:** battery %, range, charging state, the charge-limit tick; a controls grid of the main lock,
///   other switches (sentry...), covers (charge port, frunk, trunk, windows) and buttons (flash lights, horn...).
/// - **Climate:** the `climate` entity (target ±, on/off), cabin temperatures, seat/steering/defrost controls.
/// - **Charging:** charge limit, charge current, charging switch, cable lock, charger power, time to full.
/// - The wake button and connectivity sensor become the "Asleep · wake" pill.
struct KhalaCarLayout: Equatable {
    struct Climate: Equatable {
        let entityId: String
        let isOn: Bool
        let target: KhalaNumberSetting?
        let currentTemperature: Double?
        /// The mode `turn_on` would pick back (the first non-off mode), for the on/off button.
        let onMode: String?
    }

    var name: String
    var battery: Double?
    var batteryEntityId: String?
    /// "≈ 302 km"
    var rangeText: String?
    /// "Not charging", "Charging", "Complete"...
    var chargingText: String?
    var isCharging = false
    var chargeLimit: KhalaNumberSetting?
    var chargeCurrent: KhalaNumberSetting?
    var tracker: KhalaEntity?
    var wakeButtonId: String?
    /// Nil when the car reports no connectivity.
    var isAwake: Bool?
    var overview: [KhalaControl] = []
    /// Buttons Khala has no glyph for (homelink, keyless driving, novelty sounds...): tucked under one "More" tile.
    var moreControls: [KhalaControl] = []
    /// The car's own media player, opened in the media sheet from the car screen (never a home media device).
    var mediaPlayerId: String?
    var climate: Climate?
    var climateControls: [KhalaControl] = []
    var insideTemperature: Double?
    var outsideTemperature: Double?
    var chargingControls: [KhalaControl] = []
    var chargerPowerText: String?
    var timeToFull: Date?

    /// `members` are the device's entities, `attributes` the raw attributes by entity id.
    init(name: String, members: [KhalaEntity], attributes: [String: [String: Any]]) {
        self.name = name
        let visible = members.filter { !$0.isAuxiliary }.sorted { $0.entityId < $1.entityId }
        func attrs(_ entity: KhalaEntity) -> [String: Any] { attributes[entity.entityId] ?? [:] }
        func text(_ entity: KhalaEntity) -> String { (entity.entityId + " " + entity.name).lowercased() }
        func has(_ entity: KhalaEntity, _ words: String...) -> Bool { words.contains { text(entity).contains($0) } }

        // Battery, range, charging.
        if let battery = visible.first(where: {
            $0.domain == "sensor" && $0.deviceClass == "battery" && !has($0, "limit")
        }) {
            self.battery = Double(battery.state)
            self.batteryEntityId = battery.entityId
        }
        if let range = visible.first(where: { $0.domain == "sensor" && $0.deviceClass == "distance" && has($0, "range") }),
           let value = Double(range.state) {
            self.rangeText = "≈ " + KhalaText.measurement(value.rounded(), unit: range.unit)
        }
        if let charging = visible.first(where: { $0.domain == "sensor" && has($0, "charging") && Double($0.state) == nil }) {
            self.isCharging = charging.state == "charging" || charging.state == "starting"
            self.chargingText = KhalaScreenText.chargingState(charging.state)
        }
        self.chargeLimit = visible
            .first { $0.domain == "number" && ($0.deviceClass == "battery" || has($0, "charge_limit", "charge limit")) }
            .flatMap { KhalaNumberSetting($0, attributes: attrs($0)) }
        self.chargeCurrent = visible
            .first { $0.domain == "number" && $0.deviceClass == "current" && has($0, "charg") }
            .flatMap { KhalaNumberSetting($0, attributes: attrs($0)) }
        if let power = visible.first(where: { $0.domain == "sensor" && $0.deviceClass == "power" && has($0, "charg") }),
           let value = Double(power.state) {
            self.chargerPowerText = KhalaText.measurement(value, unit: power.unit)
        }
        self.timeToFull = visible
            .first { $0.domain == "sensor" && $0.deviceClass == "timestamp" && has($0, "full", "charge") }?
            .stateDate

        // Presence and sleep.
        self.tracker = visible.first { $0.domain == "device_tracker" && has($0, "location") }
            ?? visible.first { $0.domain == "device_tracker" }
        self.wakeButtonId = visible.first { $0.domain == "button" && has($0, "wake") }?.entityId
        if let status = visible.first(where: {
            $0.domain == "binary_sensor" && $0.deviceClass == "connectivity" && !has($0, "cable", "charg")
        }), !status.isUnavailable {
            self.isAwake = status.state == "on"
        }

        // Climate.
        if let climate = visible.first(where: { $0.domain == "climate" }) {
            let attributes = attrs(climate)
            let modes = KhalaValue.list(attributes["hvac_modes"]).compactMap { $0 as? String }
            var target: KhalaNumberSetting?
            if let value = KhalaValue.double(attributes["temperature"]) {
                target = KhalaNumberSetting(
                    entityId: climate.entityId,
                    title: KhalaScreenText.target,
                    value: value,
                    minimum: KhalaValue.double(attributes["min_temp"]) ?? 15,
                    maximum: KhalaValue.double(attributes["max_temp"]) ?? 28,
                    step: KhalaValue.double(attributes["target_temp_step"]) ?? 0.5,
                    unit: "°"
                )
            }
            self.climate = Climate(
                entityId: climate.entityId,
                isOn: !["off", "unavailable", "unknown"].contains(climate.state),
                target: target,
                currentTemperature: climate.temperature,
                onMode: modes.first { $0 != "off" }
            )
        }
        for sensor in visible where sensor.domain == "sensor" && sensor.deviceClass == "temperature" {
            if has(sensor, "inside", "cabin", "interior") {
                insideTemperature = Double(sensor.state)
            } else if has(sensor, "outside", "exterior", "ambient") {
                outsideTemperature = Double(sensor.state)
            }
        }

        // Controls, by tab.
        let mainLock = visible.first { $0.domain == "lock" && !has($0, "cable", "charg") }
        var overview: [KhalaControl] = []
        var more: [KhalaControl] = []
        var climateControls: [KhalaControl] = []
        var chargingControls: [KhalaControl] = []
        for entity in visible {
            guard ["lock", "switch", "cover", "button", "select"].contains(entity.domain),
                  entity.entityId != wakeButtonId,
                  let control = KhalaControl.make(entity, attributes: attrs(entity)) else { continue }
            if entity.domain == "lock", entity.entityId != mainLock?.entityId {
                chargingControls.append(control)
            } else if has(entity, "seat", "steering", "defrost", "climate", "heater", "cabin", "fan") {
                climateControls.append(control)
            } else if control.glyph == .chargePort {
                // Shown on both: it is the car's most used opening.
                overview.append(control)
                chargingControls.append(control)
            } else if entity.domain == "switch", has(entity, "charg") {
                chargingControls.append(control)
            } else if entity.domain == "select" {
                climateControls.append(control)
            } else if entity.domain == "button", control.glyph == .button {
                more.append(control)
            } else {
                overview.append(control)
            }
        }
        self.overview = overview.sorted(by: Self.tileOrder)
        self.moreControls = more.sorted(by: Self.tileOrder)
        self.mediaPlayerId = visible.first { $0.domain == "media_player" }?.entityId
        self.climateControls = climateControls.sorted(by: Self.tileOrder)
        self.chargingControls = chargingControls.sorted(by: Self.tileOrder)
    }

    /// Whether a command should wake the car first: it reports being asleep and has a wake button. Khala never
    /// wakes a car just because its screen opened.
    var needsWake: Bool { isAwake == false && wakeButtonId != nil }

    /// The car's place in words: "At home", "Away", a zone name.
    var placeText: String? {
        guard let tracker, !tracker.isUnavailable else { return nil }
        switch tracker.state {
        case "home": return KhalaScreenText.atHome
        case "not_home": return KhalaScreenText.away
        default: return KhalaText.humanized(state: tracker.state)
        }
    }

    private static let glyphOrder: [KhalaControl.Glyph] = [
        .lock, .unlock, .shield, .chargePort, .frunk, .trunk, .window, .lights, .horn, .power,
        .seat, .wheel, .defrost, .fan, .button, .generic,
    ]

    private static func tileOrder(_ lhs: KhalaControl, _ rhs: KhalaControl) -> Bool {
        let lhsRank = glyphOrder.firstIndex(of: lhs.glyph) ?? glyphOrder.count
        let rhsRank = glyphOrder.firstIndex(of: rhs.glyph) ?? glyphOrder.count
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

extension KhalaCarLayout.Climate {
    func power(on: Bool) -> KhalaServiceCall {
        KhalaServiceCall("climate", on ? "turn_on" : "turn_off", entityId: entityId)
    }

    func setTarget(_ value: Double) -> KhalaServiceCall {
        KhalaServiceCall("climate", "set_temperature", entityId: entityId, data: ["temperature": value])
    }
}
