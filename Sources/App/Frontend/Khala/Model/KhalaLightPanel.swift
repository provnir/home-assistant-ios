import Foundation
import Shared

/// The light hero (DESCRIPTORS-DESIGN.md §3, "Light (single)" / "Light group"): power, then brightness, warmth and
/// colour only as the light supports them (`LightCapabilities`, Home Assistant's own parser); a group adds one row per
/// member. Controls only, as `KhalaControlModel`s for `KhalaControlGrid`; nothing here reads a name or an id.
struct KhalaLightPanel: Equatable {
    let entityId: String
    let isGroup: Bool
    /// "On · 70% · 2700 K", "Off", "3 of 5 on".
    let subtitle: String
    /// Power first, then brightness, warmth, colour.
    let controls: [KhalaControlModel]
    /// A group's members that Home Assistant knows, in the group's order: one toggle row each, the row's state
    /// "80%" / "On" / "Off".
    let members: [KhalaControlModel]

    init(entity: KhalaEntity, attributes: [String: Any], members: [(KhalaEntity, [String: Any])] = []) {
        let capabilities = LightCapabilities(attributes: attributes)
        let isOn = entity.state == "on"
        let isGroup = !entity.groupMembers.isEmpty
        let available = !entity.isUnavailable
        entityId = entity.entityId
        self.isGroup = isGroup

        var controls: [KhalaControlModel] = []
        var power = KhalaControlModel.power(
            entity,
            title: isGroup ? KhalaScreenText.allLights : KhalaScreenText.power,
            symbolName: Self.symbol(isOn: isOn, group: isGroup)
        )
        power.stateText = isOn ? KhalaScreenText.on : KhalaText.humanized(state: entity.state)
        controls.append(power)

        let brightness = isOn ? capabilities.brightnessPercentage : 0
        if capabilities.supportsBrightness {
            var slider = KhalaControlModel(entityId: entity.entityId, title: KhalaScreenText.brightness,
                                           symbol: .sf("sun.max.fill"), kind: .slider(.brightness, value: brightness),
                                           confirm: nil)
            slider.stateText = brightness.map { KhalaSlider.brightness.text($0) } ?? ""
            slider.isAvailable = available
            controls.append(slider)
        }
        if capabilities.supportsColorTemp {
            let range = KhalaSlider.colorTemp(minKelvin: capabilities.minColorTempKelvin,
                                              maxKelvin: capabilities.maxColorTempKelvin)
            // A light in a colour mode reports no kelvin: the slider then rests where it is, unlabelled.
            let kelvin = isOn ? capabilities.colorTempKelvin : nil
            var slider = KhalaControlModel(entityId: entity.entityId, title: KhalaScreenText.warmth,
                                           symbol: .sf("thermometer.sun.fill"), kind: .slider(range, value: kelvin),
                                           confirm: nil)
            slider.stateText = kelvin.map { range.text($0) } ?? ""
            slider.isAvailable = available
            controls.append(slider)
        }
        if capabilities.supportsColor {
            let hs = KhalaValue.list(attributes["hs_color"]).compactMap(KhalaValue.double)
            let hue = isOn && hs.count == 2 ? hs[0] : nil
            let saturation = isOn && hs.count == 2 ? hs[1] : nil
            var colour = KhalaControlModel(entityId: entity.entityId, title: KhalaScreenText.colour,
                                           symbol: .sf("paintpalette.fill"),
                                           kind: .color(hue: hue, saturation: saturation), confirm: nil)
            colour.isAvailable = available
            controls.append(colour)
        }
        self.controls = controls

        self.members = members.map { member, memberAttributes in
            let memberOn = member.state == "on"
            var row = KhalaControlModel.power(member, title: member.name,
                                              symbolName: Self.symbol(isOn: memberOn, group: false))
            let percent = memberOn ? LightCapabilities(attributes: memberAttributes).brightnessPercentage : nil
            row.stateText = percent.map { KhalaSlider.brightness.text($0) }
                ?? (memberOn ? KhalaScreenText.on : KhalaText.humanized(state: member.state))
            return row
        }

        if !available {
            subtitle = KhalaText.humanized(state: entity.state)
        } else if isGroup, !members.isEmpty {
            subtitle = KhalaScreenText.membersOn(members.filter { $0.0.state == "on" }.count, of: members.count)
        } else if isOn {
            var parts = [KhalaScreenText.on]
            if let brightness, capabilities.supportsBrightness { parts.append(KhalaSlider.brightness.text(brightness)) }
            if let kelvin = capabilities.colorTempKelvin, capabilities.supportsColorTemp {
                parts.append(KhalaText.kelvin(kelvin))
            }
            subtitle = parts.joined(separator: " · ")
        } else {
            subtitle = KhalaText.humanized(state: entity.state)
        }
    }

    private static func symbol(isOn: Bool, group: Bool) -> String {
        switch (group, isOn) {
        case (true, true): return "lightbulb.2.fill"
        case (true, false): return "lightbulb.2"
        case (false, true): return "lightbulb.fill"
        case (false, false): return "lightbulb"
        }
    }
}
