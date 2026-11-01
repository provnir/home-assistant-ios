import Foundation
import Shared

/// Intent → service call (DESCRIPTORS-DESIGN.md §2, "Intent → service"), with service names from upstream
/// `Service`. The parts only upstream `Domain` knows (which services toggle a domain, groups going through
/// `homeassistant`, a domain's main action) come in as `KhalaUpstreamFacts` from the iOS bridge, so the table
/// itself runs on Linux. Controls reach it only through `KhalaConfirmGate`, which refuses an unconfirmed unlock or
/// opening; a `.confirmed` intent handed straight to the table is refused.
enum KhalaServiceTable {
    /// The call for `intent` on `entityId` in `state`, or nil when the entity can't do it.
    static func call(
        _ intent: KhalaIntent,
        entityId: String,
        state: String,
        facts: KhalaUpstreamFacts
    ) -> KhalaServiceCall? {
        let domain = entityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? entityId
        func make(_ service: Service, _ data: [String: Any] = [:], in target: String? = nil) -> KhalaServiceCall {
            KhalaServiceCall(target ?? domain, service.rawValue, entityId: entityId, data: data)
        }
        switch intent {
        case let .setOn(isOn):
            guard let service = isOn ? facts.on : facts.off else { return nil }
            return make(service, in: facts.serviceDomain)
        case .toggle:
            // `STATES_OFF` (upstream `Domain.statesOff`): closed, locked and off turn on.
            let isOff = ["closed", "locked", "off"].contains(state)
            guard let service = isOff ? facts.on : facts.off else { return nil }
            return make(service, in: facts.serviceDomain)
        case .press:
            guard let service = facts.mainAction else { return nil }
            return make(service, in: facts.serviceDomain)
        case .lock:
            return domain == "lock" ? make(.lock) : nil
        case .unlock:
            return domain == "lock" ? make(.unlock) : nil
        case .open:
            switch domain {
            case "lock": return make(.open)
            case "cover": return make(.openCover)
            case "valve": return make(.openValve)
            default: return nil
            }
        case let .set(slider, value):
            switch slider {
            case .brightness:
                return domain == "light" ? make(.turnOn, ["brightness_pct": Int(clamp(value).rounded())]) : nil
            case .position:
                return domain == "cover" ? make(.setCoverPosition, ["position": Int(clamp(value).rounded())]) : nil
            case .tilt:
                guard domain == "cover" else { return nil }
                return KhalaServiceCall(domain, "set_cover_tilt_position", entityId: entityId,
                                        data: ["tilt_position": Int(clamp(value).rounded())])
            case .percentage:
                guard domain == "fan" else { return nil }
                return make(.setPercentage, ["percentage": Int(slider.snapped(value))])
            case .colorTemp:
                guard domain == "light" else { return nil }
                return make(.turnOn, ["color_temp_kelvin": Int(slider.snapped(value))])
            case .volume:
                guard domain == "media_player" else { return nil }
                let level = (min(1, max(0, value)) * 100).rounded() / 100
                return KhalaServiceCall(domain, "volume_set", entityId: entityId, data: ["volume_level": level])
            }
        case let .setColor(hue, saturation):
            guard domain == "light" else { return nil }
            let color = [(min(360, max(0, hue)) * 10).rounded() / 10, (clamp(saturation) * 10).rounded() / 10]
            return make(.turnOn, ["hs_color": color])
        case let .setFlag(flag, isOn):
            switch (domain, flag) {
            case ("fan", .oscillate):
                return KhalaServiceCall(domain, "oscillate", entityId: entityId, data: ["oscillating": isOn])
            default: return nil
            }
        case let .setTemperature(value):
            guard domain == "climate" || domain == "water_heater" else { return nil }
            return make(.setTemperature, ["temperature": value])
        case let .setNumber(value):
            guard domain == "number" || domain == "input_number" else { return nil }
            return KhalaServiceCall(domain, "set_value", entityId: entityId, data: ["value": value])
        case let .choose(field, option):
            return choose(field, option, domain: domain, entityId: entityId)
        case let .command(command):
            return self.command(command, domain: domain, entityId: entityId, make: { make($0) })
        case .timedOn:
            // The hint's `{service, field}` decides it: the water screen sends `KhalaHeatLayout.heatCall`, built
            // from the hints file. No control produces this intent.
            return nil
        case .confirmed:
            // Only `KhalaConfirmGate` unwraps a confirmed intent, after checking it.
            return nil
        }
    }

    private static func choose(_ field: KhalaChoiceField, _ option: String, domain: String,
                               entityId: String) -> KhalaServiceCall? {
        switch field {
        case .option:
            guard domain == "select" || domain == "input_select" else { return nil }
            return KhalaServiceCall(domain, "select_option", entityId: entityId, data: ["option": option])
        case .source:
            guard domain == "media_player" else { return nil }
            return KhalaServiceCall(domain, "select_source", entityId: entityId, data: ["source": option])
        case .soundMode:
            guard domain == "media_player" else { return nil }
            return KhalaServiceCall(domain, "select_sound_mode", entityId: entityId, data: ["sound_mode": option])
        case .hvacMode:
            guard domain == "climate" else { return nil }
            return KhalaServiceCall(domain, Service.setHvacMode.rawValue, entityId: entityId,
                                    data: ["hvac_mode": option])
        case .fanMode:
            guard domain == "climate" else { return nil }
            return KhalaServiceCall(domain, Service.setFanMode.rawValue, entityId: entityId, data: ["fan_mode": option])
        case .swingMode:
            guard domain == "climate" else { return nil }
            return KhalaServiceCall(domain, Service.setSwingMode.rawValue, entityId: entityId,
                                    data: ["swing_mode": option])
        case .direction:
            guard domain == "fan" else { return nil }
            return KhalaServiceCall(domain, "set_direction", entityId: entityId, data: ["direction": option])
        case .presetMode:
            guard domain == "climate" || domain == "fan" else { return nil }
            return KhalaServiceCall(domain, Service.setPresetMode.rawValue, entityId: entityId,
                                    data: ["preset_mode": option])
        }
    }

    private static func command(_ command: KhalaCommand, domain: String, entityId: String,
                                make: (Service) -> KhalaServiceCall) -> KhalaServiceCall? {
        switch (domain, command) {
        case ("vacuum", .start): return make(.start)
        case ("vacuum", .pause): return make(.pause)
        case ("vacuum", .stop): return make(.stop)
        case ("vacuum", .returnHome): return make(.returnToBase)
        case ("vacuum", .locate): return make(.locate)
        case ("cover", .open): return make(.openCover)
        case ("cover", .close): return make(.closeCover)
        case ("cover", .stop): return make(.stopCover)
        case ("cover", .openTilt): return KhalaServiceCall("cover", "open_cover_tilt", entityId: entityId)
        case ("cover", .closeTilt): return KhalaServiceCall("cover", "close_cover_tilt", entityId: entityId)
        case ("cover", .stopTilt): return KhalaServiceCall("cover", "stop_cover_tilt", entityId: entityId)
        case ("lock", .open): return make(.open)
        case ("valve", .open): return make(.openValve)
        case ("valve", .close): return make(.closeValve)
        default: return nil
        }
    }

    private static func clamp(_ value: Double) -> Double { min(100, max(0, value)) }
}
