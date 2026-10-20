import Foundation

/// A camera as the Cameras grid and the camera picker list it: name plus a short state on the right
/// ("Person 07:35" when something was seen today, else "Clear").
struct KhalaCameraRow: Equatable, Identifiable {
    let entityId: String
    let name: String
    let stateText: String
    /// Something was detected today; the picker shows the state in the accent colour.
    let hasDetectionToday: Bool
    let isUnavailable: Bool

    var id: String { entityId }
}
