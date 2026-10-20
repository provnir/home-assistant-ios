import Combine
import Foundation
import Shared
import UIKit

/// What the Khala shell shows and the link to the web frontend it keeps mounted underneath. Native screens that
/// need the web UI (more-info dialogs, the automation editor, the camera player the web view presents) go through
/// here.
@MainActor
final class KhalaShellModel: ObservableObject {
    @Published var destination: KhalaDestination
    @Published var isMenuOpen = false

    let server: Server
    private weak var webViewController: WebViewController?
    private var cancellables = Set<AnyCancellable>()

    init(server: Server, startsOnDashboards: Bool) {
        self.server = server
        self.destination = startsOnDashboards ? .dashboards : .today
    }

    /// Called by `FrontendView` while SwiftUI builds the web view, so nothing here may publish synchronously.
    /// Like the App Labs tab bar (`NativeTabBarViewModel`), a navigation the user didn't start in the frontend
    /// (deep link, notification, App Intent) brings the web UI forward.
    func attach(_ controller: WebViewController) {
        webViewController = controller
        cancellables.removeAll()
        controller.overlayState?.externalNavigationRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.destination = .dashboards
                self?.isMenuOpen = false
            }
            .store(in: &cancellables)
    }

    /// Opens Home Assistant's more-info dialog for an entity in the web UI.
    func openMoreInfo(entityId: String) {
        openWebPath("/?\(AppConstants.QueryItems.openMoreInfoDialog.rawValue)=\(entityId)")
    }

    /// Shows the web UI on a frontend path, navigating inside the running frontend when it can.
    func openWebPath(_ path: String) {
        destination = .dashboards
        isMenuOpen = false
        webViewController?.openSidebarPath(path)
    }

    /// The app's native camera player (`CameraOverlayPresenter`, the one the frontend's `camera/show` uses).
    func openCamera(entityId: String, name: String?) {
        guard let webViewController else {
            openMoreInfo(entityId: entityId)
            return
        }
        CameraOverlayPresenter.shared.show(entityId: entityId, server: server, cameraName: name, on: webViewController)
    }
}
