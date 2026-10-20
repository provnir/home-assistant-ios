import Foundation

/// A tracker arriving at or leaving a place, from its recorded history ("Arrived home", "Left home").
struct KhalaPresenceChange: Equatable, Identifiable {
    let date: Date
    let arrived: Bool
    /// The zone, as Home Assistant names it in the tracker's state (`home`, a zone name).
    let place: String

    var id: Date { date }
}
