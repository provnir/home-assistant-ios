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

    /// Opens a destination. Screens have no back button (one leading control: the menu button), so nothing is
    /// remembered; the drawer is the way on.
    func show(_ newDestination: KhalaDestination) {
        isMenuOpen = false
        destination = newDestination
    }
}
