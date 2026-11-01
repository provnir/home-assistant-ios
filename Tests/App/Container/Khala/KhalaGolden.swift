import Foundation
@testable import HomeAssistant

/// Renders model output as stable plain text for the characterization ("same output as today") tests: one line per
/// device, route, tile or layout field, with no module names or memory addresses, so the same text is produced on
/// iOS and on Linux and a diff shows exactly what changed.
enum KhalaGolden {
    static func device(_ device: KhalaDevice) -> String {
        [
            device.id, device.name, device.category.rawValue, device.primaryEntityId, device.stateText,
            device.isPinned ? "pinned" : "detected", device.memberEntityIds.joined(separator: ","),
        ].joined(separator: " | ")
    }

    static func devices(_ devices: [KhalaDevice]) -> String {
        devices.map(device).joined(separator: "\n")
    }

    static func destination(_ destination: KhalaDestination) -> String {
        switch destination {
        case .today: return "today"
        case .cameras: return "cameras"
        case .automations: return "automations"
        case .dashboards: return "dashboards"
        case .settings: return "settings"
        case let .camera(entityId): return "camera(\(entityId))"
        case let .device(id): return "device(\(id))"
        case let .entity(entityId): return "entity(\(entityId))"
        }
    }

    static func route(_ target: KhalaRouteTarget) -> String {
        switch target {
        case let .screen(destination): return "screen " + self.destination(destination)
        case let .mediaSheet(deviceId, entityId): return "sheet \(deviceId) \(entityId)"
        }
    }

    static func plan(_ plan: KhalaServiceCallPlan?) -> String {
        plan.map { "\($0.domain).\($0.service)(\($0.entityId))" } ?? "-"
    }

    static func call(_ call: KhalaServiceCall) -> String {
        let data = call.data
            .filter { $0.key != "entity_id" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        return "\(call.name)(\(call.entityId ?? "-"))" + (data.isEmpty ? "" : "{\(data)}")
    }

    static func control(_ control: KhalaControl) -> String {
        [
            control.entityId, control.title, control.stateText, control.glyph.rawValue,
            control.isActive ? "active" : "idle", plan(control.call),
            control.options.isEmpty ? "-" : control.options.joined(separator: "/"),
            control.needsConfirmation ? "confirm" : "-",
        ].joined(separator: " | ")
    }

    static func controls(_ controls: [KhalaControl]) -> String {
        controls.map(control).joined(separator: "\n")
    }

    static func number(_ setting: KhalaNumberSetting?) -> String {
        guard let setting else { return "-" }
        return "\(setting.entityId) \(setting.title) \(setting.value) [\(setting.minimum)...\(setting.maximum) by "
            + "\(setting.step)] \(setting.unit ?? "-")"
    }

    static func optional<T>(_ value: T?) -> String {
        value.map { "\($0)" } ?? "-"
    }

    static func car(_ car: KhalaCarLayout) -> String {
        var lines = [
            "name: \(car.name)",
            "battery: \(optional(car.battery)) from \(optional(car.batteryEntityId))",
            "range: \(optional(car.rangeText))",
            "charging: \(optional(car.chargingText)) isCharging=\(car.isCharging)",
            "chargeLimit: \(number(car.chargeLimit))",
            "chargeCurrent: \(number(car.chargeCurrent))",
            "tracker: \(optional(car.tracker?.entityId)) place=\(optional(car.placeText))",
            "wake: \(optional(car.wakeButtonId)) connectivity=\(optional(car.connectivityId)) "
                + "awake=\(optional(car.isAwake))",
            "media: \(optional(car.mediaPlayerId))",
            "inside: \(optional(car.insideTemperature)) outside: \(optional(car.outsideTemperature))",
            "chargerPower: \(optional(car.chargerPowerText)) timeToFull: \(optional(car.timeToFull?.timeIntervalSince1970))",
        ]
        if let climate = car.climate {
            lines.append("climate: \(climate.entityId) on=\(climate.isOn) current=\(optional(climate.currentTemperature)) "
                + "onMode=\(optional(climate.onMode)) target=\(number(climate.target))")
        } else {
            lines.append("climate: -")
        }
        switch car.wakePlan {
        case .none: lines.append("wakePlan: none")
        case let .press(button): lines.append("wakePlan: press \(button)")
        case let .pressAndWait(button, connectivity): lines.append("wakePlan: pressAndWait \(button) \(connectivity)")
        }
        lines.append("[overview]")
        lines += car.overview.map(control)
        lines.append("[more]")
        lines += car.moreControls.map(control)
        lines.append("[climate]")
        lines += car.climateControls.map(control)
        lines.append("[charging]")
        lines += car.chargingControls.map(control)
        return lines.joined(separator: "\n")
    }

    static func heat(_ heat: KhalaHeatLayout) -> String {
        [
            "heater: \(heat.heaterEntityId) on=\(heat.isOn) unavailable=\(heat.isUnavailable) state=\(heat.stateText)",
            "remaining: \(optional(heat.remaining)) power: \(optional(heat.powerText)) duration=\(heat.supportsDuration)",
            "heat45: \(call(heat.heatCall(minutes: 45)))",
            "off: \(call(heat.offCall))",
        ].joined(separator: "\n")
    }

    static func media(_ media: KhalaMediaLayout) -> String {
        [
            "player: \(media.entityId) name=\(media.name) on=\(media.isOn) unavailable=\(media.isUnavailable)",
            "line: \(media.stateLine) power=\(media.canPower) volume=\(optional(media.volume)) muted=\(media.isMuted)",
            "sources: \(media.sources.joined(separator: "/")) source=\(optional(media.source))",
            "modes: \(media.soundModes.joined(separator: "/")) mode=\(optional(media.soundMode)) receiver=\(media.isReceiver)",
        ].joined(separator: "\n")
    }
}

extension KhalaGolden {
    /// Compares a rendering with its recorded text. With `KHALA_GOLDEN_OUT=<dir>` in the environment it also writes
    /// the rendering to `<dir>/<name>.txt`, for recording a golden deliberately after an intended change — never to
    /// make a failing characterization test pass.
    static func matches(_ name: String, _ actual: String, _ expected: String) -> Bool {
        if let directory = ProcessInfo.processInfo.environment["KHALA_GOLDEN_OUT"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".txt")
            try? actual.write(to: url, atomically: true, encoding: .utf8)
        }
        return actual == expected
    }
}
