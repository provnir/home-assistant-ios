import Foundation

/// Where taps go: every one lands on a native screen (`KhalaRouting` decides which); the web UI only shows under
/// Dashboards.
extension KhalaShellModel {
    func route(_ target: KhalaRouteTarget) {
        isMenuOpen = false
        switch target {
        case let .screen(destination):
            show(destination)
        case let .mediaSheet(deviceId, entityId):
            sheet = KhalaSheetRequest(deviceId: deviceId, entityId: entityId)
        }
    }

    /// Opens a destination. A screen opened from one of the menu's destinations remembers it for its back button;
    /// moving between screens (the camera picker) keeps the place to go back to.
    func show(_ newDestination: KhalaDestination) {
        isMenuOpen = false
        if !newDestination.isMenuDestination, destination.isMenuDestination {
            returnDestination = destination
        }
        destination = newDestination
    }

    /// The back button of a device or camera screen.
    func goBack() {
        destination = returnDestination
    }
}
