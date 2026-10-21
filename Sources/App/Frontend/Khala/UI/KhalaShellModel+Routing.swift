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

    /// Opens the full-screen still of a detection (`KhalaCaptureViewer`); `fallback` runs when the home saved no
    /// capture for it.
    func openCapture(cameraEntityId: String, cameraName: String, date: Date, fallback: @escaping () -> Void) {
        Task { @MainActor in
            guard let capture = await captures.capture(cameraEntityId: cameraEntityId, near: date) else {
                fallback()
                return
            }
            captureViewer = KhalaCaptureViewerRequest(
                cameraEntityId: cameraEntityId, cameraName: cameraName, capture: capture
            )
        }
    }

    /// "Go live" in the capture viewer: the camera's screen, on its live view.
    func goLive(from request: KhalaCaptureViewerRequest) {
        captureViewer = nil
        show(.camera(entityId: request.cameraEntityId))
    }
}
