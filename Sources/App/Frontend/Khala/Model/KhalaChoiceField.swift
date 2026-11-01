import Foundation

/// Which attribute a choice control (a dropdown menu, never a side-scroller) picks.
enum KhalaChoiceField: String, Hashable {
    case hvacMode
    case fanMode
    case presetMode
    case swingMode
    /// A fan's `direction` (`forward` / `reverse`).
    case direction
    /// `select` / `input_select` options.
    case option
    case source
    case soundMode
}
