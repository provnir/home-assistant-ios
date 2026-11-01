import Foundation

/// A second on/off setting of an entity beside its power (a fan's oscillation), so it gets its own control slot and
/// its own pending entry instead of sharing the power toggle's.
enum KhalaFlag: String, Hashable {
    /// `fan.oscillate` `oscillating`.
    case oscillate

    /// The attribute that reports it.
    var attribute: String {
        switch self {
        case .oscillate: return "oscillating"
        }
    }
}
