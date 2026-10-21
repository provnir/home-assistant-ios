import Foundation

/// Khala's user-facing copy and the formatting of states, durations and times. Kept in one Foundation-only place
/// (English for now) so a later pass can move it to `L10n` in one go without touching the views or the model.
enum KhalaText {
    // MARK: - Copy

    static let today = "Today"
    static let cameras = "Cameras"
    static let automations = "Automations"
    static let dashboards = "Dashboards"
    static let settings = "Settings"
    static let serverSettings = "Home Assistant settings"
    static let devices = "DEVICES"
    static let dashboardsSection = "DASHBOARDS"
    static let views = "Views"
    static let chooseDashboard = "Choose a dashboard or view"
    static let search = "Search"
    static let openMenu = "Open menu"
    static let closeMenu = "Close menu"
    static let rightNow = "Right now"
    static let now = "Now"
    static let sunrise = "Sunrise"
    static let sunset = "Sunset"
    static let allClear = "all clear"
    static let automation = "Automation"
    static let editDevices = "Edit"
    static let noDevices = "No devices yet"
    static let automationsPending = "Native automations are on the way. Until then they open in Home Assistant."
    static let openAutomations = "Open automations"
    static let devicesTitle = "Devices"
    static let pinnedDevices = "Pinned devices"
    static let pinnedDevicesFooter = """
    Pinned devices come first in the menu and on the Now card. The role picks the glyph and colour; the label \
    replaces the entity's name.
    """
    static let addDevice = "Add a device"
    static let addDeviceFooter = "Any entity can be pinned: a relay that runs the water heater, a car's battery sensor, ..."
    static let label = "Label"
    static let role = "Role"
    static let done = "Done"
    static let homeAssistantSection = "HOME ASSISTANT"
    static let thisAppSection = "THIS APP"
    static let thisApp = "This app"
    static let searchSettings = "Search app and server settings"
    static let searchAllSettings = "Search all settings"
    static let aboutKhala = "About Khala"
    static let moreAppSettings = "More app settings"
    static let serverSettingsUnavailable = "Home Assistant's settings need an administrator account."
    static let more = "More"

    /// "1 update", "3 updates".
    static func updates(_ count: Int) -> String {
        count == 1 ? "1 update" : "\(count) updates"
    }

    /// "1 repair", "2 repairs".
    static func repairs(_ count: Int) -> String {
        count == 1 ? "1 repair" : "\(count) repairs"
    }

    /// The server card's second line: "Home Assistant 2026.10.2 · homeassistant.local".
    static func serverSubtitle(version: String?, host: String?) -> String {
        let product = version.map { "Home Assistant \($0)" } ?? "Home Assistant"
        guard let host, !host.isEmpty else { return product }
        return "\(product) · \(host)"
    }

    /// The Settings screen's footer: "Khala 2026.10.2 (17.1)".
    static func appVersion(_ version: String?, build: String?) -> String {
        switch (version, build) {
        case let (version?, build?): return "Khala \(version) (\(build))"
        case let (version?, nil): return "Khala \(version)"
        default: return "Khala"
        }
    }

    static func noResults(_ query: String) -> String {
        "Nothing in settings matches \u{201C}\(query)\u{201D}"
    }

    /// An untitled view's name when the frontend gave none.
    static func view(number: Int) -> String {
        "View \(number)"
    }

    static func cameraCount(_ count: Int) -> String {
        count == 1 ? "1 camera" : "\(count) cameras"
    }

    static func detections(_ count: Int) -> String {
        count == 1 ? "1 detection today" : "\(count) detections today"
    }

    // MARK: - States

    /// A state as a short label: "Off", "Playing", "Away", "—" for unknown.
    static func humanized(state: String) -> String {
        switch state {
        case "unknown", "": return "—"
        case "unavailable": return "Unavailable"
        case "not_home": return "Away"
        default:
            let spaced = state.replacingOccurrences(of: "_", with: " ")
            return spaced.prefix(1).uppercased() + spaced.dropFirst()
        }
    }

    /// The short state text a device row or chip shows for `entity`.
    static func stateText(for entity: KhalaEntity) -> String {
        if entity.isUnavailable {
            return humanized(state: entity.state)
        }
        switch entity.domain {
        case "sensor", "number", "input_number":
            guard let value = Double(entity.state) else { return humanized(state: entity.state) }
            return measurement(value, unit: entity.unit)
        case "water_heater", "climate":
            if let temperature = entity.temperature {
                return "\(Int(temperature.rounded()))°"
            }
            return humanized(state: entity.state)
        default:
            return humanized(state: entity.state)
        }
    }

    /// "65%", "21°", "301 km", "0.5 kW".
    static func measurement(_ value: Double, unit: String?) -> String {
        let number = value.rounded() == value || abs(value) >= 100
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value)
        guard let unit, !unit.isEmpty else { return number }
        if unit == "%" { return "\(number)%" }
        if unit.hasPrefix("°") { return "\(Int(value.rounded()))°" }
        return "\(number) \(unit)"
    }

    /// Words for a `weather.*` condition.
    static func weatherCondition(_ state: String) -> String {
        switch state {
        case "clear-night": return "clear"
        case "partlycloudy": return "partly cloudy"
        case "lightning-rainy": return "stormy"
        case "snowy-rainy": return "sleet"
        case "windy-variant": return "windy"
        case "exceptional": return "unusual weather"
        default: return state.replacingOccurrences(of: "-", with: " ")
        }
    }

    /// What was seen, from an `event.*` entity's `event_type` and device class.
    static func detectionNoun(eventType: String?, deviceClass: String?) -> String {
        let type = (eventType ?? "").lowercased()
        if deviceClass == "doorbell" || type.contains("ring") || type.contains("doorbell") { return "Ring" }
        if type.contains("human") || type.contains("person") || type.contains("people") { return "Person" }
        if type.contains("vehicle") || type.contains("car") { return "Vehicle" }
        if type.contains("pet") || type.contains("animal") || type.contains("dog") || type.contains("cat") {
            return "Animal"
        }
        return "Motion"
    }

    // MARK: - Durations and times

    /// "5 h 32 m", "32 m", "1 h", "now".
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, 0): return "now"
        case (0, _): return "\(rest) m"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest) m"
        }
    }

    /// 24-hour "HH:mm", as in the design. The timeline's time column is 44 pt wide.
    static func time(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
