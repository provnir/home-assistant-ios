import Foundation
import Shared

/// The climate hero (DESCRIPTORS-DESIGN.md §3, "Climate"): the target temperature as a − value + stepper (clamped
/// to the entity's own range, half degrees shown), the HVAC mode as a dropdown, then fan mode, preset and swing only
/// when the entity supports them (`ClimateEntityFeature`, Home Assistant's own bits, and a non-empty list). The
/// subtitle says what it is doing and the room's temperature: "Cooling · now 26°".
///
/// Upstream `ClimateControlState` reads the same attributes but needs `L10n`, so it can't run on Linux; the bridge
/// still clamps every target through it on iOS. The defaults here are the same as its own (core's: 7–35°, 0.5°).
struct KhalaClimatePanel: Equatable {
    static let defaultMinimum = 7.0
    static let defaultMaximum = 35.0
    static let defaultStep = 0.5

    let entityId: String
    /// "Cooling · now 26°", "Heat · now 18.5°", "Off · now 24°".
    let subtitle: String
    /// Target first, then mode, fan mode, preset, swing.
    let controls: [KhalaControlModel]

    init(entity: KhalaEntity, attributes: [String: Any]) {
        let features = ClimateEntityFeature(rawValue: KhalaValue.int(attributes["supported_features"]) ?? 0)
        let available = !entity.isUnavailable
        entityId = entity.entityId

        func strings(_ key: String) -> [String] {
            KhalaValue.list(attributes[key]).compactMap { $0 as? String }
        }
        func choice(_ field: KhalaChoiceField, title: String, symbol: String, current: String?,
                    options: [String]) -> KhalaControlModel {
            var control = KhalaControlModel(entityId: entity.entityId, title: title, symbol: .sf(symbol),
                                            kind: .choice(current: current, options: options, field: field),
                                            confirm: nil)
            control.stateText = current.map { KhalaText.humanized(state: $0) } ?? ""
            control.isAvailable = available
            return control
        }

        var controls: [KhalaControlModel] = []
        // A single target. A heat/cool range (`target_temp_low`/`_high`) is not drawn yet; the mode still is.
        if features.contains(.targetTemperature), let target = KhalaValue.double(attributes["temperature"]) {
            var setting = KhalaNumberSetting(
                entityId: entity.entityId,
                title: KhalaScreenText.target,
                value: target,
                minimum: KhalaValue.double(attributes["min_temp"]) ?? Self.defaultMinimum,
                maximum: KhalaValue.double(attributes["max_temp"]) ?? Self.defaultMaximum,
                step: KhalaValue.double(attributes["target_temp_step"]) ?? Self.defaultStep,
                unit: "°"
            )
            setting.showsTenths = true
            var stepper = KhalaControlModel.stepper(setting, symbolName: "thermometer.medium")
            stepper.isAvailable = available
            controls.append(stepper)
        }
        let modes = strings("hvac_modes")
        if !modes.isEmpty {
            controls.append(choice(.hvacMode, title: KhalaScreenText.mode, symbol: "power",
                                   current: available ? entity.state : nil, options: modes))
        }
        let fanModes = strings("fan_modes")
        if features.contains(.fanMode), !fanModes.isEmpty {
            controls.append(choice(.fanMode, title: KhalaScreenText.fanMode, symbol: "fanblades",
                                   current: KhalaValue.string(attributes["fan_mode"]), options: fanModes))
        }
        let presets = strings("preset_modes")
        if features.contains(.presetMode), !presets.isEmpty {
            controls.append(choice(.presetMode, title: KhalaScreenText.preset, symbol: "list.bullet",
                                   current: KhalaValue.string(attributes["preset_mode"]), options: presets))
        }
        let swings = strings("swing_modes")
        if features.contains(.swingMode), !swings.isEmpty {
            controls.append(choice(.swingMode, title: KhalaScreenText.swing, symbol: "arrow.up.and.down",
                                   current: KhalaValue.string(attributes["swing_mode"]), options: swings))
        }
        self.controls = controls

        guard available else {
            subtitle = KhalaText.humanized(state: entity.state)
            return
        }
        // What it is doing (`hvac_action`) when it says; else its mode.
        let action = KhalaValue.string(attributes["hvac_action"])
        var parts = [KhalaText.humanized(state: action ?? entity.state)]
        if let current = KhalaValue.double(attributes["current_temperature"]) {
            parts.append(KhalaScreenText.nowTemperature(KhalaText.tenths(current) + "°"))
        }
        subtitle = parts.joined(separator: " · ")
    }
}
