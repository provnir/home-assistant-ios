import Combine
import Foundation
import Shared
import UIKit

/// What the Khala shell shows and the link to the web frontend it keeps mounted underneath. Native screens that
/// need the web UI (more-info dialogs, the automation editor, the camera player the web view presents) go through
/// here.
@MainActor
final class KhalaShellModel: ObservableObject {
    @Published var destination: KhalaDestination {
        didSet {
            applyStatusBarStyle()
            applyFrontendCorners()
        }
    }

    @Published var isMenuOpen = false {
        didSet {
            applyStatusBarStyle()
            applyFrontendCorners()
        }
    }

    /// Routing (`KhalaShellModel+Routing`): where a device/camera screen's back button returns, and the media
    /// sheet on display.
    @Published var returnDestination: KhalaDestination = .today
    @Published var sheet: KhalaSheetRequest?

    /// The web frontend is up (connected or loaded), so its header — with the menu button `KhalaShell`'s script
    /// keeps there — is on screen. While it isn't (loading, offline), the shell's own edge swipe stands in.
    @Published private(set) var isFrontendReady = false

    /// The frontend asked for the app's menu (its header button, or the app's edge swipe bounced back as
    /// `sidebar/show`). The view opens the drawer with its own animation.
    let menuRequests = PassthroughSubject<Void, Never>()

    let server: Server
    private weak var webViewController: WebViewController?
    private var cancellables = Set<AnyCancellable>()
    private var frontendMenuRequest: AnyCancellable?

    init(server: Server, startsOnDashboards: Bool) {
        self.server = server
        self.destination = startsOnDashboards ? .dashboards : .today
        // `sidebar/show` from the frontend lands here because the app answers `hasSidebar` while the shell is
        // on (`KhalaShell.isEnabled`); see `WebViewExternalMessageHandler`'s `.sidebarShow`.
        frontendMenuRequest = NativeTabBarState.shared.moreRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.menuRequests.send() }
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
        controller.overlayState?.$connectionState
            .map { $0 == .connected || $0 == .loaded }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isFrontendReady = $0 }
            .store(in: &cancellables)
        applyStatusBarStyle()
    }

    /// The web view's controller decides the status-bar style for the whole window (SwiftUI defers to it). Over
    /// Khala's own ground — a native screen, or the menu — the system default (ink in light mode) is the one
    /// that reads; on the web UI the frontend's theme decides again.
    private func applyStatusBarStyle() {
        guard let webViewController else { return }
        let style: UIStatusBarStyle? = destination == .dashboards && !isMenuOpen ? nil : .default
        guard webViewController.statusBarStyleOverride != style else { return }
        webViewController.statusBarStyleOverride = style
        webViewController.setNeedsStatusBarAppearanceUpdate()
    }

    /// The web UI's card gets the drawer's rounded corners while the menu is open over it. Done on the web
    /// view controller's own layer (a plain corner clip, settled with the drawer) rather than with a SwiftUI
    /// mask, which would render the web view offscreen for as long as it is on screen.
    private func applyFrontendCorners() {
        guard let view = webViewController?.view else { return }
        let radius = isMenuOpen && destination == .dashboards
            ? CGFloat(KhalaDrawerMath.cardRadius)
            : 0
        guard view.layer.cornerRadius != radius else { return }
        view.layer.cornerCurve = .continuous
        if radius > 0 { view.layer.masksToBounds = true }
        UIView.animate(
            withDuration: KhalaDrawerMath.settleDuration,
            animations: { view.layer.cornerRadius = radius },
            completion: { _ in
                if view.layer.cornerRadius == 0 { view.layer.masksToBounds = false }
            }
        )
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
