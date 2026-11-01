import SFSafeSymbols
import Shared
import SwiftUI
import UIKit

/// Khala's root for a connected server: a menu panel underneath and the screen card above it (the Zoe app's phone
/// drawer pattern). The card shows Today, the native screens, or — for Dashboards — the app's web frontend under
/// Khala's own header (`KhalaDashboardHeaderView`; the frontend's toolbar is hidden). The frontend stays mounted
/// underneath the native screens the whole time so deep links, notifications, Settings and the camera player keep
/// working exactly as upstream wires them.
///
/// Same initializer as `HomeAssistantView`, so hooking it in is a one-word change in `ContainerView`. Off on Mac
/// Catalyst and in kiosk mode, where it is just the web frontend.
struct KhalaShellView: View {
    private let server: Server
    private let initialPath: String?
    private let appCoordinator: AppCoordinator?
    private let onWebViewController: (WebViewController) -> Void
    /// Decided once: flipping it would rebuild the web view.
    private let isEnabled: Bool

    @StateObject private var shell: KhalaShellModel
    @StateObject private var home: KhalaHomeViewModel
    @Environment(\.appSettingsPresenter) private var appSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchFocusRequest = 0
    @State private var showsDeviceSettings = false
    @State private var showsAbout = false
    /// An app settings screen shown in a sheet over the shell (the container has no navigation stack).
    @State private var appSettingsSheetItem: SettingsItem?

    init(
        server: Server,
        initialPath: String?,
        appCoordinator: AppCoordinator? = nil,
        onWebViewController: @escaping (WebViewController) -> Void
    ) {
        self.server = server
        self.initialPath = initialPath
        self.appCoordinator = appCoordinator
        self.onWebViewController = onWebViewController
        self.isEnabled = KhalaShell.isEnabled
        // A launch that already names a frontend page (deep link, restored path) lands on it, not on Today.
        self._shell = StateObject(wrappedValue: KhalaShellModel(server: server, startsOnDashboards: initialPath != nil))
        self._home = StateObject(wrappedValue: KhalaHomeViewModel(server: server))
    }

    var body: some View {
        if isEnabled {
            drawer
        } else {
            frontend
        }
    }

    // MARK: - Pieces

    /// The stock web frontend, unchanged. Built in exactly one place per branch so its identity never changes.
    private var frontend: some View {
        HomeAssistantView(server: server, initialPath: initialPath, appCoordinator: appCoordinator) { [shell] controller in
            onWebViewController(controller)
            shell.attach(controller)
        }
    }

    /// Laid out like the Zoe app's phone drawer (`SideDrawer`): one full-window menu ground, the menu panel on it,
    /// and the screen card above. Everything that is ground — the menu's wash, the card's own ground, the card's
    /// rounded mask and its shadow plate — reaches the display's edges, behind the status bar and the home
    /// indicator; content (the menu's list, the screens, the menu button) stays inside the safe area.
    ///
    /// The card's motion is UIKit's (`KhalaDrawer`: one pan on the hosting view, a velocity-carrying spring); this
    /// body only lays the pieces out. Only `KhalaDrawerStage` and `KhalaDrawerRounding` follow the motion, frame by
    /// frame.
    private var drawer: some View {
        GeometryReader { proxy in
            let openWidth = CGFloat(KhalaDrawerMath.openWidth(container: Double(proxy.size.width)))

            ZStack(alignment: .topLeading) {
                // The whole window, not just the panel's width: a corner of the moving card never exposes a
                // differently shaded strip (Zoe's PHONE-DRAWER report).
                KhalaGround(style: .menu)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                menu
                    .frame(width: openWidth)
                    .accessibilityHidden(!shell.isMenuOpen)
                    // VoiceOver's two-finger scrub closes the open menu.
                    .accessibilityAction(.escape) { shell.setMenuOpen(false) }
                    // The media sheet (theater, speakers, a car's player) hangs off the menu, which is always
                    // mounted, so it opens over any screen — the web UI included.
                    .sheet(item: $shell.sheet) { request in
                        KhalaMediaSheet(
                            entityId: request.entityId,
                            name: home.devices.first { $0.id == request.deviceId }?.name,
                            live: home.live,
                            actions: KhalaScreenActions(server: server),
                            onClose: { shell.sheet = nil }
                        )
                    }

                KhalaDrawerStage(drawer: shell.drawer) {
                    card
                }
            }
            // The drawer's coordinate space and the hook its pan is installed through (touch-transparent).
            .background(KhalaDrawerAnchor(drawer: shell.drawer).ignoresSafeArea())
        }
        .onAppear {
            KhalaShell.settingsListeners += 1
            home.start()
            if shell.destination != .dashboards {
                // Today has no Home Assistant logo for the launch splash to morph into.
                LaunchSplashOverlayState.shared.fadeOut()
            }
        }
        .onDisappear {
            KhalaShell.settingsListeners -= 1
            home.stop()
        }
        .onReceive(shell.menuRequests) { _ in shell.setMenuOpen(true) }
        .sheet(isPresented: $showsAbout) {
            NavigationStack {
                AboutView()
                    .khalaSettingsAppearance()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            CloseButton { showsAbout = false }
                        }
                    }
            }
        }
        .sheet(isPresented: Binding(
            get: { appSettingsSheetItem != nil },
            set: { if !$0 { appSettingsSheetItem = nil } }
        )) {
            if let item = appSettingsSheetItem {
                NavigationStack {
                    item.destinationView
                        .injectingViewControllerProvider()
                        .khalaSettingsAppearance()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                CloseButton { appSettingsSheetItem = nil }
                            }
                        }
                }
            }
        }
        // Detection captures: the cards' thumbnails and the full-screen still viewer.
        .environment(\.khalaCaptures, shell.captures)
        .khalaStillCover(item: $shell.captureViewer) { request in
            KhalaCaptureViewer(
                request: request,
                source: shell.captures,
                calendar: home.calendar,
                onClose: { shell.captureViewer = nil },
                onLive: { shell.goLive(from: request) }
            )
        }
        .sheet(isPresented: $showsDeviceSettings) {
            KhalaDeviceSettingsView(
                serverId: server.identifier.rawValue,
                entityNames: home.entityNames,
                assignments: home.assignments,
                onSave: { home.setAssignments($0) }
            )
        }
    }

    private var menu: some View {
        KhalaMenuView(
            homeName: server.info.name,
            summary: home.timeline.summary,
            userName: home.userName,
            destination: shell.destination,
            cameraCount: home.cameras.count,
            automationCount: home.automationCount,
            devices: home.devices,
            areas: home.areas,
            isOpen: shell.isMenuOpen,
            searchFocusRequest: searchFocusRequest,
            dashboards: shell.dashboards,
            dashboardIcons: shell.dashboardIcons,
            highlightedDashboardId: shell.highlightedDashboardId,
            onDashboard: { dashboard in
                withAnimation(settleAnimation) {
                    shell.openDashboard(dashboard)
                }
            },
            isSettingsSelected: shell.isSettingsHighlighted,
            onSelect: { destination in
                if destination == shell.destination { shell.nowScrollRequest += 1 }
                withAnimation(settleAnimation) {
                    shell.destination = destination
                    shell.isMenuOpen = false
                }
            },
            onDevice: { device in
                withAnimation(settleAnimation) {
                    shell.route(KhalaRouting.target(for: device, cameras: home.cameras))
                }
            },
            onEditDevices: { showsDeviceSettings = true },
            onSettings: {
                withAnimation(settleAnimation) {
                    shell.show(.settings)
                }
            }
        )
    }

    /// The screen card: the web frontend (always mounted), a native screen over it, the pinned menu button and,
    /// while the menu is open, the catcher that closes it.
    private var card: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                // Hidden, not removed, under a native screen: it stays mounted (deep links, notifications, the
                // camera player) but its header can't show through the status-bar band or the card's rounded
                // corners. Its own corners are rounded by the model on the UIKit layer while the card moves
                // (`applyFrontendCorners`) — a SwiftUI mask here would re-render the web view offscreen on every
                // frame it scrolls.
                frontend
                    .opacity(shell.destination == .dashboards ? 1 : 0)
                    .accessibilityHidden(shell.destination != .dashboards)

                if shell.destination != .dashboards {
                    KhalaDrawerRounding(drawer: shell.drawer) {
                        ZStack {
                            KhalaGround()
                            nativeContent
                        }
                    }
                    .transition(.opacity)
                }

                // Over the web UI: Khala's own header in place of the frontend's (hidden by `KhalaFrontendScript`),
                // once the frontend is up — the stand-by screen covers everything before that.
                // Over a settings page (or History, Logbook, ...) whose own toolbar the script lifted: Khala's page
                // chrome — large title, search, tabs, "+" (`KhalaPageHeaderView`).
                if shell.isWebScreen {
                    if let page = shell.pageHeader {
                        KhalaPageHeaderView(
                            header: page,
                            pageId: shell.frontendState?.path ?? shell.frontendPath ?? "",
                            onBack: { withAnimation(settleAnimation) { shell.goBackFromPage() } },
                            onAction: { shell.perform($0) },
                            onSearch: { shell.searchPage($0) },
                            onTab: { shell.openPageTab($0) }
                        )
                        .transition(.opacity)
                    } else {
                        KhalaDashboardHeaderView(
                            header: shell.dashboardHeader,
                            icons: shell.dashboardIcons,
                            onBack: { shell.goBackInFrontend() },
                            onDashboard: { shell.openDashboard($0) },
                            onView: { view, prefix in shell.openView(view, prefix: prefix) },
                            onAction: { shell.perform($0) }
                        )
                        .transition(.opacity)
                    }
                }

                // Pinned top-leading in the safe area, above the content and never part of its flow: the one
                // leading control on every screen. Over the web UI the dashboards header swaps it for Back while
                // the frontend is on a sub-page or dialog, and the leading-edge swipe goes Back too (`KhalaDrawer`).
                if shell.destination != .dashboards || (shell.isWebScreen && !shell.showsBackInHeader) {
                    KhalaGlassButton(symbol: .sidebarLeft, accessibilityLabel: KhalaText.openMenu) {
                        shell.setMenuOpen(true)
                    }
                    .padding(.leading, Self.menuButtonInset.leading)
                    .padding(.top, Self.menuButtonInset.top)
                    .transition(.opacity)
                }
            }
            // While the menu is open it is the only thing VoiceOver reads, with the catcher below as its way out.
            .accessibilityHidden(shell.isMenuOpen)

            // While the menu is open the card's content takes no touches: a tap on the visible card closes the
            // menu. Drags (here, on the menu, anywhere) are the drawer's pan, on the hosting view.
            if shell.isMenuOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { shell.setMenuOpen(false) }
                    .accessibilityElement()
                    .accessibilityLabel(KhalaText.closeMenu)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { shell.setMenuOpen(false) }
                    .accessibilityAction(.escape) { shell.setMenuOpen(false) }
            }
        }
    }

    /// Where the shell pins the menu button inside the safe area. Native screens leave room for it above their
    /// title (`9 + 44 + 4` in `KhalaScreen` and `KhalaTodayView`).
    static let menuButtonInset = EdgeInsets(top: 9, leading: 16, bottom: 0, trailing: 0)

    @ViewBuilder
    private var nativeContent: some View {
        switch shell.destination {
        case .today:
            KhalaTodayView(
                timeline: home.timeline,
                now: home.now,
                calendar: home.calendar,
                onMenu: { shell.setMenuOpen(true) },
                onSearch: {
                    shell.setMenuOpen(true)
                    searchFocusRequest += 1
                },
                onItem: { handle($0) },
                onDevice: { device in shell.route(KhalaRouting.target(for: device, cameras: home.cameras)) },
                scrollRequest: shell.nowScrollRequest
            )
        case .cameras:
            KhalaCamerasView(
                cameras: home.cameras,
                live: home.live,
                actions: KhalaScreenActions(server: server),
                now: home.now,
                calendar: home.calendar,
                onMenu: { shell.setMenuOpen(true) },
                onCamera: { entityId in shell.show(.camera(entityId: entityId)) }
            )
        case .automations:
            KhalaPlaceholderView(
                title: KhalaText.automations,
                message: KhalaText.automationsPending,
                actionTitle: KhalaText.openAutomations,
                onMenu: { shell.setMenuOpen(true) },
                action: { shell.openWebPath("/config/automation/dashboard") }
            )
        case .dashboards:
            EmptyView()
        case .settings:
            KhalaSettingsView(
                serverName: server.info.name,
                settings: shell.settings,
                live: home.live,
                onServerPage: { path in
                    withAnimation(settleAnimation) {
                        shell.openServerPage(path)
                    }
                },
                onAppItem: { openAppSettings($0) },
                onAbout: { showsAbout = true },
                onMoreAppSettings: { openAllAppSettings() }
            )
        case .camera, .device, .entity:
            KhalaDetailScreen(destination: shell.destination, server: server, home: home, live: home.live, shell: shell)
        }
    }

    // MARK: - Actions

    /// One of the companion app's settings screens, hosted as it is in a sheet over the shell, in Khala's
    /// appearance (`KhalaSettingsAppearance`). The container has no navigation stack to push onto: upstream
    /// presents Settings as a sheet only.
    private func openAppSettings(_ item: SettingsItem) {
        appSettingsSheetItem = item
    }

    /// The app's complete settings list (Location, Sensors, Widgets, Siri, Watch, ...): upstream's own Settings
    /// sheet.
    private func openAllAppSettings() {
        appSettings?.presentSettings()
    }

    private func handle(_ item: KhalaTimelineItem) {
        switch item.kind {
        case let .detection(eventEntityId, cameraEntityId):
            // The still the home saved for the detection; its camera's screen when there is none.
            guard let cameraEntityId else { return route(entityId: eventEntityId) }
            let name = home.live.entitiesById[cameraEntityId]?.name ?? cameraEntityId
            shell.openCapture(cameraEntityId: cameraEntityId, cameraName: name, date: item.date) {
                route(entityId: cameraEntityId)
            }
        case .scheduled, .timestamp:
            if let target = item.targetEntityId {
                route(entityId: target)
            }
        case .sunrise, .sunset, .now:
            break
        }
    }

    /// Every tap lands on a native screen (`KhalaRouting`); the web UI only shows under Dashboards.
    private func route(entityId: String) {
        shell.route(KhalaRouting.target(
            forEntityId: entityId,
            entities: home.live.entities,
            devices: home.devices,
            automationConfigs: home.live.automationConfigs
        ))
    }

    // MARK: - Drawer motion

    /// What content changes made from the drawer (a menu selection, Back) animate with: the drawer's own settle
    /// spring, or a short ease with Reduce Motion. The card's motion itself is `KhalaDrawer`'s.
    private var settleAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: KhalaDrawerMath.settleDuration, dampingFraction: 1)
    }
}
