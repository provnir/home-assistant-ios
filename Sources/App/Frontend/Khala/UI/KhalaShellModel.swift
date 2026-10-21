import Combine
import Foundation
import HAKit
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

    /// Routing (`KhalaShellModel+Routing`): the media sheet on display.
    @Published var sheet: KhalaSheetRequest?

    /// The web frontend is up (connected or loaded), so the native dashboards header is drawn over it. While it
    /// isn't (loading, offline) the stand-by screen covers it and the shell's own edge swipe stands in.
    @Published private(set) var isFrontendReady = false {
        didSet { applyStatusBarStyle() }
    }

    // MARK: Dashboards (`KhalaShellModel+Dashboards`)

    /// The user's dashboards, as Home Assistant's own sidebar lists them (order, hidden panels, default first).
    @Published private(set) var dashboards: [KhalaDashboard] = []
    /// Their sidebar icons, by `KhalaDashboard.id`.
    private(set) var dashboardIcons: [String: FrontendIcon] = [:]
    /// The frontend page on screen (the app's URL observation).
    @Published private(set) var frontendPath: String? {
        didSet {
            rememberDashboard()
            frontendPageChanged()
        }
    }
    /// What `KhalaFrontendScript` last reported: views, dialog, actions, a lifted page's chrome.
    @Published private(set) var frontendState: KhalaFrontendState? {
        didSet {
            rememberDashboard()
            frontendPageChanged()
        }
    }
    /// The frontend's more-info dialog is up (external bus `more_info/opened`).
    @Published private(set) var isMoreInfoOpen = false
    /// The dashboard last on screen, where the "Dashboards" destination and a dead-end back return to.
    private(set) var lastDashboardId: String?
    /// Home Assistant's sidebar, mirrored by the app's own `MacSidebarViewModel` (also behind the App Labs tab
    /// bar): panels, the user's order and hidden panels, the default dashboard. Created on the first attach.
    private var sidebar: MacSidebarViewModel?
    private var sidebarObservation: AnyCancellable?
    /// Home Assistant's own settings (`/config`, the panel whose component is `config`), opened in the web UI
    /// under Khala's header. Nil until the panels load, and for users who aren't admins (`get_panels` leaves the
    /// admin-only panel out for them).
    @Published private(set) var serverSettings: KhalaDashboard?
    private var panelsToken: HACancellable?

    // MARK: Settings (`KhalaShellModel+Settings`)

    /// The Settings screen's server facts (capabilities, repairs, host); kept across visits.
    let settings: KhalaSettingsModel
    /// The Home Assistant page the Settings screen opened last, where it landed after the frontend's own
    /// redirect; Back there returns to Settings. Nil once the web UI is used for something else.
    @Published var settingsEntryPath: String?
    /// The path Settings asked for, and until when a redirect below it still counts as its landing.
    /// Detection captures (stills saved by the home's automations), for cards and the viewer.
    let captures: KhalaMediaSourceCaptures
    /// The full-screen capture viewer, when one is open.
    @Published var captureViewer: KhalaCaptureViewerRequest?
    /// The page chrome held on screen while a chosen tab's page loads (`KhalaPageTabHold`).
    @Published var pageTabHold: KhalaPageTabHold?
    var settingsRequestedPath: String?
    var settingsLandingDeadline: Date?
    private var settingsRequest: AnyCancellable?

    /// The frontend asked for the app's menu (the app's edge swipe on the web UI, bounced back as `sidebar/show`).
    /// The view opens the drawer with its own animation.
    let menuRequests = PassthroughSubject<Void, Never>()

    let server: Server
    private(set) weak var webViewController: WebViewController?
    private var cancellables = Set<AnyCancellable>()
    private var frontendMenuRequest: AnyCancellable?

    deinit {
        panelsToken?.cancel()
    }

    init(server: Server, startsOnDashboards: Bool) {
        self.server = server
        self.destination = startsOnDashboards ? .dashboards : .today
        self.settings = KhalaSettingsModel(server: server)
        self.captures = KhalaMediaSourceCaptures(server: server)
        // `sidebar/show` from the frontend lands here because the app answers `hasSidebar` while the shell is
        // on (`KhalaShell.isEnabled`); see `WebViewExternalMessageHandler`'s `.sidebarShow`.
        frontendMenuRequest = NativeTabBarState.shared.moreRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.menuRequests.send() }
        // The frontend's own "Companion app" settings entry (see `ContainerView`'s `onShowSettings`).
        settingsRequest = KhalaShell.settingsRequests
            .sink { [weak self] in self?.show(.settings) }
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
        controller.overlayState?.$currentPath
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.frontendPath = $0 }
            .store(in: &cancellables)
        controller.overlayState?.$isMoreInfoDialogOpen
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isMoreInfoOpen = $0 }
            .store(in: &cancellables)
        controller.khalaBridge.state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.frontendState = $0 }
            .store(in: &cancellables)
        if let overlayState = controller.overlayState {
            startDashboards(overlayState: overlayState)
        }
        applyStatusBarStyle()
    }

    /// The web view's controller decides the status-bar style for the whole window (SwiftUI defers to it). Over
    /// Khala's own chrome — a native screen, the menu, or the native header over the web UI — the system default
    /// (ink in light mode) is the one that reads; only while the frontend isn't up (stand-by) does its theme
    /// decide.
    private func applyStatusBarStyle() {
        guard let webViewController else { return }
        let style: UIStatusBarStyle? = destination == .dashboards && !isMenuOpen && !isFrontendReady ? nil : .default
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

    /// Starts mirroring Home Assistant's sidebar into `dashboards` (once per shell).
    private func startDashboards(overlayState: WebFrontendOverlayState) {
        guard sidebar == nil else { return }
        let sidebar = MacSidebarViewModel(server: server, overlayState: overlayState)
        // Legacy per-browser sidebar settings the frontend still honours; same reader as `HomeAssistantViewModel`.
        sidebar.readLocalStorage = { [weak self] key, completion in
            guard let webViewController = self?.webViewController else {
                completion(nil)
                return
            }
            webViewController.evaluateJavaScript("window.localStorage.getItem('\(key)')") { result, _ in
                completion(result as? String)
            }
        }
        sidebarObservation = sidebar.$mainItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in self?.setDashboards(items) }
        self.sidebar = sidebar
        sidebar.start()

        // The settings panel's url from the panels list itself rather than a hard-coded `/config`.
        panelsToken = Current.api(for: server)?.connection.caches.panels.subscribe { [weak self] _, panels in
            let panel = panels.allPanels.first { $0.component == "config" }
            Task { @MainActor [weak self] in
                let settings = panel.map { KhalaDashboard(id: $0.path, title: KhalaText.serverSettings) }
                if self?.serverSettings != settings {
                    self?.serverSettings = settings
                }
            }
        }
    }

    private func setDashboards(_ items: [MacSidebarItem]) {
        var icons: [String: FrontendIcon] = [:]
        let dashboards = items.compactMap { item -> KhalaDashboard? in
            guard case .panel = item.kind else { return nil }
            icons[item.id] = item.icon
            return KhalaDashboard(id: item.id, title: item.title)
        }
        dashboardIcons = icons
        if self.dashboards != dashboards {
            self.dashboards = dashboards
        }
        rememberDashboard()
    }

    private func rememberDashboard() {
        let path = frontendState?.path ?? frontendPath
        if let id = KhalaFrontendPath.dashboard(for: path, in: dashboards)?.id {
            lastDashboardId = id
        }
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
