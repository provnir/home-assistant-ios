import Foundation

/// A car's screens (mockup `DayCar`) read from the entities of its Home Assistant device — whatever the
/// integration exposes, nothing assumed: tiles exist only for entities that exist.
///
/// What each entity is comes from the hints file (`KhalaHints`, keyed on registry platform + translation key), then
/// from domain and device class. Names and ids are never read. Types are code; which car is which is data.
/// - **Overview:** battery %, range, charging state, the charge-limit tick; a controls grid of the main lock, the
///   other switches, covers and buttons with a glyph (a hint's, or the domain's). Buttons with no glyph of their
///   own go under one "More" tile.
/// - **Climate:** the `climate` entity (target ±, on/off), cabin temperatures, the controls hinted `climate`.
/// - **Charging:** charge limit, charge current, charger power, time to full, the controls hinted `charging`.
/// - The hinted wake button and connectivity sensor become the "Asleep · wake" pill.
/// A car with no hints (another integration) still gets Overview — every control, the battery by device class —
/// and the Climate and Charging tabs only when something lands on them (`tabs`).
struct KhalaCarLayout: Equatable {
    struct Climate: Equatable {
        let entityId: String
        let isOn: Bool
        let target: KhalaNumberSetting?
        let currentTemperature: Double?
        /// The mode `turn_on` would pick back (the first non-off mode), for the on/off button.
        let onMode: String?
    }

    /// The screen's bottom-bar sections, in order.
    enum Tab: Equatable {
        case overview, climate, charging
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
    /// The car's connectivity sensor (on = awake), whatever its state.
    var connectivityId: String?
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
    init(
        name: String,
        members: [KhalaEntity],
        attributes: [String: [String: Any]],
        hints: KhalaHints = .builtIn
    ) {
        self.name = name
        let visible = members.filter { !$0.isAuxiliary }.sorted { $0.entityId < $1.entityId }
        func attrs(_ entity: KhalaEntity) -> [String: Any] { attributes[entity.entityId] ?? [:] }
        func hint(_ entity: KhalaEntity) -> KhalaHint? { hints.hint(for: entity) }
        /// The member the hints give `role`, on `domain`.
        func member(_ role: KhalaHintRole, _ domain: String) -> KhalaEntity? {
            visible.first { $0.domain == domain && hint($0)?.role == role }
        }
        /// A member known only by domain and device class, when no hint names one: it must carry no role of its
        /// own (a hinted usable-battery sensor is not THE battery).
        func plain(_ domain: String, deviceClass: String) -> KhalaEntity? {
            visible.first { $0.domain == domain && $0.deviceClass == deviceClass && hint($0)?.role == nil }
        }

        // Battery, range, charging.
        if let battery = member(.battery, "sensor") ?? plain("sensor", deviceClass: "battery") {
            self.battery = Double(battery.state)
            self.batteryEntityId = battery.entityId
        }
        if let range = member(.range, "sensor"), let value = Double(range.state) {
            self.rangeText = "≈ " + KhalaText.measurement(value.rounded(), unit: range.unit)
        }
        if let charging = member(.chargingState, "sensor"), Double(charging.state) == nil {
            self.isCharging = charging.state == "charging" || charging.state == "starting"
            self.chargingText = KhalaScreenText.chargingState(charging.state)
        }
        self.chargeLimit = (member(.chargeLimit, "number") ?? plain("number", deviceClass: "battery"))
            .flatMap { KhalaNumberSetting($0, attributes: attrs($0)) }
        self.chargeCurrent = (member(.chargeCurrent, "number") ?? plain("number", deviceClass: "current"))
            .flatMap { KhalaNumberSetting($0, attributes: attrs($0)) }
        if let power = member(.chargerPower, "sensor"), let value = Double(power.state) {
            self.chargerPowerText = KhalaText.measurement(value, unit: power.unit)
        }
        self.timeToFull = member(.timeToFull, "sensor")?.stateDate

        // Presence and sleep.
        self.tracker = member(.location, "device_tracker") ?? visible.first { $0.domain == "device_tracker" }
        self.wakeButtonId = member(.wake, "button")?.entityId
        if let status = member(.connectivity, "binary_sensor") {
            self.connectivityId = status.entityId
            if !status.isUnavailable { self.isAwake = status.state == "on" }
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
        insideTemperature = member(.insideTemperature, "sensor").flatMap { Double($0.state) }
        outsideTemperature = member(.outsideTemperature, "sensor").flatMap { Double($0.state) }

        // Controls, by tab: where the hint puts them, else Overview (glyph-less buttons: More). The main lock is the
        // first lock the hints don't send elsewhere (a charge cable lock goes to Charging).
        var tabs: [KhalaCarSection: [KhalaControl]] = [:]
        for entity in visible {
            guard ["lock", "switch", "cover", "button", "select"].contains(entity.domain),
                  entity.entityId != wakeButtonId,
                  let control = KhalaControl.make(entity, attributes: attrs(entity), hints: hints) else { continue }
            let sections = hint(entity)?.sections ?? []
            if !sections.isEmpty {
                for section in sections {
                    tabs[section, default: []].append(control)
                }
            } else if entity.domain == "button", control.glyph == .button {
                tabs[.more, default: []].append(control)
            } else {
                tabs[.overview, default: []].append(control)
            }
        }
        self.overview = (tabs[.overview] ?? []).sorted(by: Self.tileOrder)
        self.moreControls = (tabs[.more] ?? []).sorted(by: Self.tileOrder)
        self.mediaPlayerId = visible.first { $0.domain == "media_player" }?.entityId
        self.climateControls = (tabs[.climate] ?? []).sorted(by: Self.tileOrder)
        self.chargingControls = (tabs[.charging] ?? []).sorted(by: Self.tileOrder)
    }

    /// Overview always; Climate and Charging only when something lands on them, so a car the hints don't know
    /// shows plain tabs instead of empty ones (one tab left: no bar). A known car has all three.
    var tabs: [Tab] {
        var tabs: [Tab] = [.overview]
        if climate != nil || !climateControls.isEmpty { tabs.append(.climate) }
        if chargeLimit != nil || chargeCurrent != nil || chargerPowerText != nil || timeToFull != nil
            || chargingText != nil || !chargingControls.isEmpty {
            tabs.append(.charging)
        }
        return tabs
    }

    /// How to get the car awake before reading it or sending it a command (Nir: a refresh must wake the car to
    /// read its status, and commands can't reach a sleeping car).
    var wakePlan: KhalaCarWakePlan {
        guard let wakeButtonId else { return .none }
        guard let connectivityId else { return .press(button: wakeButtonId) }
        // Asleep, offline or unknown (an unavailable sensor): wake and wait until the sensor says it's online.
        return isAwake == true ? .none : .pressAndWait(button: wakeButtonId, connectivity: connectivityId)
    }

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

/// What waking a car takes (`KhalaCarLayout.wakePlan`).
enum KhalaCarWakePlan: Equatable {
    /// Awake already, or nothing to wake it with.
    case none
    /// Press the wake button, then wait until the connectivity sensor reports the car online.
    case pressAndWait(button: String, connectivity: String)
    /// Press the wake button; there is no sensor to wait on.
    case press(button: String)

    /// How long to wait for a car to come online before saying it didn't wake.
    static let timeout: TimeInterval = 60
}

/// Where a car screen's wake-and-read stands (`KhalaCarView`).
enum KhalaCarSyncState: Equatable {
    case idle
    /// The wake button was pressed; waiting for the car to come online.
    case waking
    /// `homeassistant.update_entity` is out.
    case updating
    /// The car didn't come online in time; "Retry" runs it again.
    case didntWake

    /// The subtitle's freshness part. While a refresh runs it says so ("Waking car…", "Updating…"), whatever the
    /// entities' `last_updated` says — pressing the wake button alone moves that — and only once it has finished
    /// "Updated just now" (build 24.1: the pill said "Waking car…" while the subtitle already said "Updated just now").
    func freshnessText(lastUpdated: Date?, now: Date) -> String? {
        switch self {
        case .waking: return KhalaScreenText.wakingCar
        case .updating: return KhalaScreenText.updating
        case .didntWake: return KhalaScreenText.carDidntWake
        case .idle: return lastUpdated.map { KhalaScreenText.updated($0, now: now) }
        }
    }
}
