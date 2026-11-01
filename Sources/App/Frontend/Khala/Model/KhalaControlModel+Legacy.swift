import Foundation
import Shared

extension KhalaControlModel {
    /// The grid's model of a 41.1 tile (`KhalaControl`, still built by `KhalaCarLayout` and the generic screen until
    /// slice 5 moves detection onto descriptors): same glyph, title, state, active look, enabled state and confirm
    /// step, now driven by intents instead of a ready-made call.
    init(_ control: KhalaControl, entity: KhalaEntity, attributes: [String: Any]) {
        let kind: Kind
        var directions = Directions.both
        var confirm: KhalaConfirm?
        var isAvailable = control.call != nil
        switch entity.domain {
        case "lock":
            kind = .lock(isLocked: entity.state == "locked",
                         canOpen: LockCapabilities(attributes: attributes).supportsOpen)
            confirm = .unlock
        case "cover":
            // A tile opens a closed cover and closes the rest, each only when the cover supports it (a frunk that
            // only opens). Opening asks first.
            let features = CoverCapabilities(attributes: attributes)
            let reported = attributes["supported_features"] != nil
            directions = Directions(on: !reported || features.supportsOpen, off: !reported || features.supportsClose)
            kind = .toggle(isOn: control.isActive)
            isAvailable = entity.state != "unavailable"
            confirm = .open(deviceClass: entity.deviceClass)
        case "button":
            kind = .press
        case "select", "input_select":
            kind = .choice(current: entity.state, options: control.options, field: .option)
            isAvailable = !control.options.isEmpty
        default:
            kind = .toggle(isOn: control.isActive)
        }
        self.init(entityId: control.entityId, title: control.title, symbol: .sf(control.glyph.symbolName), kind: kind,
                  confirm: confirm)
        stateText = control.stateText
        self.isAvailable = isAvailable
        self.directions = directions
    }

    /// A device's main on/off switch (the generic screen's Power row).
    static func power(_ entity: KhalaEntity, title: String, symbolName: String) -> KhalaControlModel {
        var model = KhalaControlModel(entityId: entity.entityId, title: title, symbol: .sf(symbolName),
                                      kind: .toggle(isOn: entity.state == "on"), confirm: nil)
        model.stateText = KhalaText.humanized(state: entity.state)
        model.isAvailable = entity.state != "unavailable"
        return model
    }
}

extension KhalaControlModel {
    /// A − value + control for a `number` or a climate target (the car's charge limit, current and cabin target).
    static func stepper(_ setting: KhalaNumberSetting, symbolName: String) -> KhalaControlModel {
        var model = KhalaControlModel(entityId: setting.entityId, title: setting.title, symbol: .sf(symbolName),
                                      kind: .stepper(setting), confirm: nil)
        model.stateText = setting.text
        return model
    }

    /// The setting a stepper shows (pending value included), nil for other kinds.
    var numberSetting: KhalaNumberSetting? {
        guard case let .stepper(setting) = kind else { return nil }
        return setting
    }

    /// Whether a toggle shows on (pending included); nil for other kinds.
    var toggleIsOn: Bool? {
        guard case let .toggle(isOn) = kind else { return nil }
        return isOn
    }
}
