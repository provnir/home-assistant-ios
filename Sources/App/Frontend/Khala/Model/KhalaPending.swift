import Foundation

/// One control's optimistic overlay (DESCRIPTORS-DESIGN.md §2): shown from the tap until Home Assistant echoes
/// it, refuses it, or `KhalaPendingBook.echoTimeout` passes after its answer.
struct KhalaPending: Equatable {
    let entityId: String
    let value: KhalaPendingValue
    let echo: KhalaPendingEcho
    let startedAt: Date
    /// When Home Assistant accepted the call; nil while it is still out (a car may be waking first).
    var answeredAt: Date?
    /// The live state already showed the change while the call was out.
    var isEchoed = false

    var isInFlight: Bool { answeredAt == nil }
}
