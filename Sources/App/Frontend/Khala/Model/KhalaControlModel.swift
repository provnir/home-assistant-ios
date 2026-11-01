import Foundation

/// One control on any surface — device screens, the car's tabs, the generic screen, the media sheet — as the single
/// `KhalaControlGrid` draws it (DESCRIPTORS-DESIGN.md §2). A tap becomes a `KhalaIntent` (`tapIntent`), which the
/// iOS-side `KhalaUpstreamBridge` turns into a service call; `pending` is the optimistic overlay
/// (`KhalaPendingBook`) the control shows until Home Assistant echoes it, fails it or it times out.
struct KhalaControlModel: Identifiable, Equatable {
    enum Kind: Equatable {
        case toggle(isOn: Bool)
        /// The current value, 0...100 (volume 0...1 as HA reports it); nil when unknown.
        case slider(KhalaSlider, value: Double?)
        case stepper(KhalaNumberSetting)
        case choice(current: String?, options: [String], field: KhalaChoiceField)
        case press
        /// `canOpen` from `LockCapabilities.supportsOpen`.
        case lock(isLocked: Bool, canOpen: Bool)
        case commands([KhalaCommand])
        /// A light's colour (hue 0...360, saturation 0...100), nil when it reports none (off, white mode).
        case color(hue: Double?, saturation: Double?)
        /// A second on/off setting beside the power (a fan's oscillation).
        case flag(KhalaFlag, isOn: Bool)
    }

    /// Which way a two-way control (toggle, lock) can go: a frunk that only opens, a cover without close.
    struct Directions: Equatable {
        /// Turn on / open / lock.
        var on = true
        /// Turn off / close / unlock.
        var off = true

        static let both = Directions()
    }

    let entityId: String
    /// `KhalaEntity.nameWithoutDevice`: HA's own, already localised name.
    let title: String
    let symbol: KhalaGlyph
    let kind: Kind
    /// Asks before the dangerous direction (unlocking, opening). Which intent that is: `confirmation(for:)`.
    let confirm: KhalaConfirm?
    /// The state in words ("Locked", "On", "…"), shown on lock tiles and read by VoiceOver.
    var stateText: String = ""
    /// False while Home Assistant reports the entity unavailable (or a lock's state is still unknown).
    var isAvailable = true
    var directions: Directions = .both
    /// The optimistic overlay; set by `showing(_:)`.
    var pending: KhalaPending?

    /// Unique per control, not per entity: a media player is a power toggle, a volume slider and two choices.
    /// Also the key of its `KhalaPendingBook` entry, so a volume change never shows on the power switch.
    var id: String { "\(entityId)#\(slot)" }

    /// Which of an entity's controls this is.
    var slot: String {
        switch kind {
        case .toggle: return "power"
        case .slider: return "slider"
        case .stepper: return "value"
        case let .choice(_, _, field): return field.rawValue
        case .press: return "press"
        case .lock: return "lock"
        case .commands: return "commands"
        case .color: return "color"
        case let .flag(flag, _): return flag.rawValue
        }
    }

    /// The entity's domain (`switch`, `cover`…).
    var domain: String {
        entityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? entityId
    }
}

extension KhalaControlModel {
    /// Drawn tinted: on, open, locked, a select with a value, a press on its way.
    var isActive: Bool {
        switch kind {
        case let .toggle(isOn): return isOn
        case let .flag(_, isOn): return isOn
        case let .lock(isLocked, _): return isLocked
        case let .choice(current, _, _):
            guard let current else { return false }
            return !["off", "unavailable", "unknown"].contains(current)
        case .press, .commands: return pending != nil
        case .slider, .stepper, .color: return false
        }
    }

    /// Whether a tap can do anything right now (on the state as shown, pending included).
    var isEnabled: Bool {
        guard isAvailable else { return false }
        switch kind {
        case let .toggle(isOn): return isOn ? directions.off : directions.on
        case let .lock(isLocked, _): return isLocked ? directions.off : directions.on
        case let .choice(_, options, _): return !options.isEmpty
        case .press, .slider, .stepper, .commands, .color, .flag: return true
        }
    }

    /// What a plain tap asks for: always explicit (`setOn(false)`, `.unlock`), never a blind toggle, so a
    /// repeated tap can't flip a state back by accident. Nil for controls a tap doesn't drive (sliders, steppers,
    /// choices open their own UI).
    var tapIntent: KhalaIntent? {
        guard isEnabled else { return nil }
        switch kind {
        case let .toggle(isOn): return .setOn(!isOn)
        case let .lock(isLocked, _): return isLocked ? .unlock : .lock
        case .press: return .press
        case let .flag(flag, isOn): return .setFlag(flag, !isOn)
        case .slider, .stepper, .choice, .commands, .color: return nil
        }
    }

    /// The intent for a value picked on a slider or stepper: a climate target, a `number`, a light's brightness…
    func valueIntent(_ value: Double) -> KhalaIntent? {
        switch kind {
        case let .slider(slider, _): return .set(slider, value)
        case .stepper: return domain == "climate" ? .setTemperature(value) : .setNumber(value)
        case .toggle, .choice, .press, .lock, .commands, .color, .flag: return nil
        }
    }

    /// The question to ask before `intent`, or nil to send it at once. Unlocking always asks; opening asks for a
    /// control that declares it (a cover tile opens on `setOn(true)`).
    func confirmation(for intent: KhalaIntent) -> KhalaConfirm? {
        switch (confirm, intent) {
        case (.unlock?, .unlock): return .unlock
        case let (.open(deviceClass)?, .open), let (.open(deviceClass)?, .setOn(true)):
            return .open(deviceClass: deviceClass)
        default: return nil
        }
    }

    /// The control as it should look with `pending` laid over it: a toggle already flipped, a stepper already on
    /// its new value. Nil `pending` gives the plain control.
    func showing(_ pending: KhalaPending?) -> KhalaControlModel {
        var shown = self
        shown.pending = pending
        guard let pending else { return shown }
        switch (kind, pending.value) {
        case let (.toggle, .on(isOn)):
            shown = shown.with(kind: .toggle(isOn: isOn), stateText: isOn ? KhalaScreenText.on : KhalaScreenText.off)
        case let (.lock(_, canOpen), .locked(isLocked)):
            shown = shown.with(
                kind: .lock(isLocked: isLocked, canOpen: canOpen),
                stateText: KhalaText.humanized(state: isLocked ? "locked" : "unlocked"),
                symbol: .sf(isLocked ? KhalaControl.Glyph.lock.symbolName : KhalaControl.Glyph.unlock.symbolName)
            )
        case let (.stepper(setting), .number(value)):
            shown = shown.with(kind: .stepper(setting.with(value: value)), stateText: setting.with(value: value).text)
        case let (.slider(slider, _), .number(value)):
            shown = shown.with(kind: .slider(slider, value: value), stateText: stateText)
        case let (.flag(flag, _), .on(isOn)):
            shown = shown.with(kind: .flag(flag, isOn: isOn),
                               stateText: isOn ? KhalaScreenText.on : KhalaScreenText.off)
        case let (.color, .color(hue, saturation)):
            shown = shown.with(kind: .color(hue: hue, saturation: saturation), stateText: stateText)
        case let (.choice(_, options, field), .option(option)):
            shown = shown.with(
                kind: .choice(current: option, options: options, field: field),
                stateText: KhalaText.humanized(state: option)
            )
        default:
            break
        }
        return shown
    }

    /// The pending entry `intent` starts on this control: what it shows and what proves it landed. Nil for an
    /// intent with nothing to show (`timedOn`, decided by hint data in a later slice).
    func pendingValue(for intent: KhalaIntent) -> (value: KhalaPendingValue, echo: KhalaPendingEcho)? {
        switch intent {
        case let .setOn(isOn):
            return (.on(isOn), KhalaPendingEcho.power(domain: domain, on: isOn))
        case .toggle:
            guard case let .toggle(isOn) = kind else { return nil }
            return (.on(!isOn), KhalaPendingEcho.power(domain: domain, on: !isOn))
        case .lock:
            return (.locked(true), .state(["locked", "locking"]))
        case .unlock:
            return (.locked(false), .state(["unlocked", "unlocking", "open", "opening"]))
        case .open:
            return domain == "lock"
                ? (.locked(false), .state(["open", "opening", "unlocked"]))
                : (.on(true), .state(["open", "opening"]))
        case .press, .command:
            return (.pressed, .none)
        case let .set(slider, value):
            switch slider {
            case .volume: return (.number(value), .attributeNumber("volume_level", value, tolerance: 0.011))
            case .brightness: return (.number(value), .attributeNumber("brightness", value * 2.55, tolerance: 3))
            case .position: return (.number(value), .attributeNumber("current_position", value, tolerance: 1))
            case .percentage: return (.number(value), .attributeNumber("percentage", value, tolerance: 1))
            case .colorTemp:
                // Lights store mireds, so the kelvin they report back rarely matches to the unit.
                return (.number(value), .attributeNumber("color_temp_kelvin", value, tolerance: max(30, value * 0.02)))
            }
        case let .setColor(hue, saturation):
            // Lights round colours their own way; Home Assistant's answer ends it.
            return (.color(hue: hue, saturation: saturation), .none)
        case let .setFlag(flag, isOn):
            return (.on(isOn), .attributeBool(flag.attribute, isOn))
        case let .setTemperature(value):
            return (.number(value), .attributeNumber("temperature", value, tolerance: 0.01))
        case let .setNumber(value):
            return (.number(value), .stateNumber(value, tolerance: 0.0001))
        case let .choose(field, option):
            return (.option(option), KhalaPendingEcho.choice(field, option))
        case .timedOn:
            return nil
        }
    }

    private func with(kind: Kind, stateText: String, symbol: KhalaGlyph? = nil) -> KhalaControlModel {
        var copy = KhalaControlModel(
            entityId: entityId, title: title, symbol: symbol ?? self.symbol, kind: kind, confirm: confirm
        )
        copy.stateText = stateText
        copy.isAvailable = isAvailable
        copy.directions = directions
        copy.pending = pending
        return copy
    }
}
