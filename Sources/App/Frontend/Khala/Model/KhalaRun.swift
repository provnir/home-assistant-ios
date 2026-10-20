import Foundation

/// A stretch of time a device was on, from its recorded history.
struct KhalaRun: Equatable, Identifiable {
    let start: Date
    /// Nil while it is still on.
    let end: Date?

    var id: Date { start }

    func duration(now: Date) -> TimeInterval {
        (end ?? now).timeIntervalSince(start)
    }
}
