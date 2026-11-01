import Foundation

/// Which attribute a choice control (a dropdown menu, never a side-scroller) picks.
enum KhalaChoiceField: String, Hashable {
    case hvacMode
    case fanMode
    case presetMode
    case swingMode
    /// `select` / `input_select` options.
    case option
    case source
    case soundMode
}
