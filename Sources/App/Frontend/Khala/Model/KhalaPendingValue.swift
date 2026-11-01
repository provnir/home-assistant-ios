import Foundation

/// What a control shows while its call is out (`KhalaPending`): the state the user asked for.
enum KhalaPendingValue: Equatable {
    /// A toggle, a cover tile (on = open), a climate's power.
    case on(Bool)
    case locked(Bool)
    /// A stepper's or slider's new value (volume 0...1, the rest in the control's own unit).
    case number(Double)
    /// A choice's new option.
    case option(String)
    /// A light's new colour (hue 0...360, saturation 0...100).
    case color(hue: Double, saturation: Double)
    /// A press or command on its way; nothing to echo.
    case pressed
}
