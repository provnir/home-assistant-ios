import Foundation

/// The media sheet the shell shows over the current screen: the device it belongs to (`KhalaDevice.id`, for the
/// name) and the `media_player` entity it controls.
struct KhalaSheetRequest: Equatable, Identifiable {
    let deviceId: String
    let entityId: String

    var id: String { entityId }
}
