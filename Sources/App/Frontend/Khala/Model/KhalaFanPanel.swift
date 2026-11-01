import Foundation
import Shared

/// The fan hero (DESCRIPTORS-DESIGN.md §3, "Fan"): power, a speed slider that snaps to the fan's
/// `percentage_step` (`FanCapabilities`), then oscillation, direction and preset only as the fan supports them.
struct KhalaFanPanel: Equatable {
    /// `FanEntityFeature` bits Home Assistant's `FanCapabilities` doesn't parse (it reads SET_SPEED only).
    private enum Feature: Int {
        case oscillate = 2
        case direction = 4
        case presetMode = 8
    }

    let entityId: String
    /// "On · 50%", "Off".
    let subtitle: String
    let controls: [KhalaControlModel]

    init(entity: KhalaEntity, attributes: [String: Any]) {
        let capabilities = FanCapabilities(attributes: attributes)
        let features = KhalaValue.int(attributes["supported_features"]) ?? 0
        let isOn = entity.state == "on"
        let available = !entity.isUnavailable
        entityId = entity.entityId

        var controls: [KhalaControlModel] = []
        var power = KhalaControlModel.power(entity, title: KhalaScreenText.power, symbolName: "fanblades.fill")
        power.stateText = isOn ? KhalaScreenText.on : KhalaText.humanized(state: entity.state)
        controls.append(power)

        let slider = KhalaSlider.percentage(step: capabilities.percentageStep)
        let speed = isOn ? capabilities.speedPercentage.map(slider.snapped) : 0
        if capabilities.supportsSpeedPercentage {
            var control = KhalaControlModel(entityId: entity.entityId, title: KhalaScreenText.speed,
                                            symbol: .sf(Self.speedSymbol),
                                            kind: .slider(slider, value: speed), confirm: nil)
            control.stateText = speed.map(slider.text) ?? ""
            control.isAvailable = available
            controls.append(control)
        }
        if features & Feature.oscillate.rawValue != 0 {
            let oscillating = KhalaValue.bool(attributes[KhalaFlag.oscillate.attribute]) ?? false
            var control = KhalaControlModel(entityId: entity.entityId, title: KhalaScreenText.oscillate,
                                            symbol: .sf("arrow.left.and.right"),
                                            kind: .flag(.oscillate, isOn: oscillating), confirm: nil)
            control.stateText = oscillating ? KhalaScreenText.on : KhalaScreenText.off
            control.isAvailable = available
            controls.append(control)
        }
        if features & Feature.direction.rawValue != 0 {
            let direction = KhalaValue.string(attributes["direction"])
            var control = KhalaControlModel(entityId: entity.entityId, title: KhalaScreenText.direction,
                                            symbol: .sf("arrow.triangle.2.circlepath"),
                                            kind: .choice(current: direction, options: ["forward", "reverse"],
                                                          field: .direction),
                                            confirm: nil)
            control.stateText = direction.map { KhalaText.humanized(state: $0) } ?? ""
            control.isAvailable = available
            controls.append(control)
        }
        let presets = KhalaValue.list(attributes["preset_modes"]).compactMap { $0 as? String }
        if features & Feature.presetMode.rawValue != 0, !presets.isEmpty {
            let preset = KhalaValue.string(attributes["preset_mode"])
            var control = KhalaControlModel(entityId: entity.entityId, title: KhalaScreenText.preset,
                                            symbol: .sf("list.bullet"),
                                            kind: .choice(current: preset, options: presets, field: .presetMode),
                                            confirm: nil)
            control.stateText = preset.map { KhalaText.humanized(state: $0) } ?? ""
            control.isAvailable = available
            controls.append(control)
        }
        self.controls = controls

        if isOn, let speed, capabilities.supportsSpeedPercentage {
            subtitle = "\(KhalaScreenText.on) · \(slider.text(speed))"
        } else {
            subtitle = isOn ? KhalaScreenText.on : KhalaText.humanized(state: entity.state)
        }
    }

    /// The speed slider's glyph. The gauge needle is SF Symbols 5 (iOS 17); iOS 16 draws the speedometer.
    static var speedSymbol: String {
        if #available(iOS 17, macOS 14, *) { return "gauge.with.dots.needle.50percent" }
        return "speedometer"
    }
}
