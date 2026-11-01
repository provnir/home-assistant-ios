import Foundation

/// What the user asked a control for, independent of Home Assistant service names (DESCRIPTORS-DESIGN.md §2).
/// Model produces intents and is tested on Linux; the iOS-only bridge of slice 2 turns them into service calls.
enum KhalaIntent: Equatable {
    case toggle
    case setOn(Bool)
    case press
    case set(KhalaSlider, Double)
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
}
