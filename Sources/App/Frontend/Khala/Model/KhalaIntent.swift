import Foundation

/// What the user asked a control for, independent of Home Assistant service names (DESCRIPTORS-DESIGN.md §2).
/// Model produces intents and is tested on Linux; the iOS-only bridge of slice 2 turns them into service calls.
enum KhalaIntent: Equatable {
    case toggle
    case setOn(Bool)
    case press
    case set(KhalaSlider, Double)
    /// `light.turn_on` `hs_color`: hue 0...360, saturation 0...100.
    case setColor(hue: Double, saturation: Double)
    /// A second on/off setting beside the power (a fan's oscillation).
    case setFlag(KhalaFlag, Bool)
    case setTemperature(Double)
    /// `number` / `input_number` `set_value`.
    case setNumber(Double)
    case choose(KhalaChoiceField, String)
    case command(KhalaCommand)
    case lock
    case unlock
    case open
    /// The hint's `timedOn {service, field}` decides the call (a boiler's timer), not code.
    case timedOn(minutes: Int)
    /// `intent`, after the user answered its confirmation (unlocking, opening). Only the confirmation dialog
    /// (`KhalaConfirming`) makes it; `KhalaConfirmGate` refuses an intent that needs one and arrives without it.
    indirect case confirmed(KhalaIntent)
}

extension KhalaIntent {
    /// The intent without its confirmation wrapper: what is actually asked for.
    var unconfirmed: KhalaIntent {
        if case let .confirmed(inner) = self { return inner.unconfirmed }
        return self
    }

    /// Whether the user confirmed it.
    var isConfirmed: Bool {
        if case .confirmed = self { return true }
        return false
    }
}
