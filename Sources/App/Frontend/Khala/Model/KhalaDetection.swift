import Foundation

/// One thing a camera saw: an `event.*` firing, from its current state or its recorded history.
struct KhalaDetection: Equatable, Identifiable {
    let eventEntityId: String
    let date: Date
    /// "Person", "Vehicle", "Ring", "Motion".
    let noun: String
    /// The event entity's own name without the camera's, e.g. "Field detection".
    let source: String

    var id: String { "\(eventEntityId)@\(Int(date.timeIntervalSince1970 * 1000))" }
}
