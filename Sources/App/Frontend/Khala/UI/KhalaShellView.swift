import SFSafeSymbols
import Shared
import SwiftUI
import UIKit

/// Khala's root for a connected server: a menu panel underneath and the screen card above it (the Zoe app's phone
/// drawer pattern). The card shows Today, the interim native screens, or — for Dashboards — the app's stock web
/// frontend, which stays mounted underneath the native screens the whole time so deep links, notifications,
/// Settings and the camera player keep working exactly as upstream wires them.
///
/// Same initializer as `HomeAssistantView`, so hooking it in is a one-word change in `ContainerView`. Off on Mac
/// Catalyst and in kiosk mode, where it is just the web frontend.
struct KhalaShellView: View {
    private let server: Server
    private let initialPath: String?
    private let onWebViewController: (WebViewController) -> Void
    /// Decided once: flipping it would rebuild the web view.
    private let isEnabled: Bool

    @StateObject private var shell: KhalaShellModel
    @StateObject private var home: KhalaHomeViewModel
    @Environment(\.appSettingsPresenter) private var appSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var dragTravel: CGFloat = 0
    @State private var isDragging = false
    @State private var searchFocusRequest = 0
    @State private var showsDeviceSettings = false

    init(server: Server, initialPath: String?, onWebViewController: @escaping (WebViewController) -> Void) {
        self.server = server
        self.initialPath = initialPath
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
        HomeAssistantView(server: server, initialPath: initialPath) { [shell] controller in
            onWebViewController(controller)
            shell.attach(controller)
        }
    }

    /// Laid out like the Zoe app's phone drawer (`SideDrawer`): one full-window menu ground, the menu panel on it,
    /// and the screen card above. Everything that is ground — the menu's wash, the card's own ground, the card's
    /// rounded mask and its shadow plate — reaches the display's edges, behind the status bar and the home
    /// indicator; content (the menu's list, the screens, the menu button) stays inside the safe area.
    private var drawer: some View {
        GeometryReader { proxy in
            let openWidth = CGFloat(KhalaDrawerMath.openWidth(container: Double(proxy.size.width)))
            let sign: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
            let progress = CGFloat(KhalaDrawerMath.progress(
                isOpen: shell.isMenuOpen,
                travel: Double(dragTravel),
                openWidth: Double(openWidth)
            ))
            let offset = progress * openWidth * sign
            let radius = CGFloat(KhalaDrawerMath.cornerRadius(progress: Double(progress)))
            let cardShape = RoundedRectangle(cornerRadius: radius, style: .continuous)

            ZStack(alignment: .topLeading) {
                // The whole window, not just the panel's width: a corner of the moving card never exposes a
                // differently shaded strip (Zoe's PHONE-DRAWER report).
                KhalaGround(style: .menu)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                menu
                    .frame(width: openWidth)
                    .accessibilityHidden(!shell.isMenuOpen)
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

                // The card's edge shadow, on a plain shape so the moving card itself is never shadowed.
                cardShape
                    .fill(KhalaTheme.groundFlat)
                    .shadow(
                        color: KhalaTheme.shadow.opacity(0.16 * min(1, Double(progress) * 4)),
                        radius: 13,
                        x: -6 * sign,
                        y: 2
                    )
                    .ignoresSafeArea()
                    .offset(x: offset)
                    .allowsHitTesting(false)

                card(sign: sign, shape: cardShape)
                    .offset(x: offset)
            }
        }
        .onAppear {
            home.start()
            if shell.destination != .dashboards {
                // Today has no Home Assistant logo for the launch splash to morph into.
                LaunchSplashOverlayState.shared.fadeOut()
            }
        }
        .onDisappear { home.stop() }
        .onReceive(shell.menuRequests) { _ in settle(open: true) }
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
            isOpen: shell.isMenuOpen,
            searchFocusRequest: searchFocusRequest,
            onSelect: { destination in
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
                settle(open: false)
                appSettings?.presentSettings()
            }
        )
    }

    /// The screen card: the web frontend (always mounted), a native screen over it, the pinned menu button, and
    /// the drawer's gesture layer.
    private func card(sign: CGFloat, shape: RoundedRectangle) -> some View {
        ZStack(alignment: .topLeading) {
            // Hidden, not removed, under a native screen: it stays mounted (deep links, notifications, the camera
            // player) but its header can't show through the status-bar band or the card's rounded corners. Its
            // own corners are rounded by the model on the UIKit layer while the menu is open over it — a SwiftUI
            // mask here would re-render the web view offscreen on every frame it scrolls.
            frontend
                .opacity(shell.destination == .dashboards ? 1 : 0)
                .accessibilityHidden(shell.destination != .dashboards)

            if shell.destination != .dashboards {
                ZStack {
                    KhalaGround()
                    nativeContent
                }
                // The mask reaches the display's edges, so the ground (and content scrolled under the bars) shows
                // behind the status bar and the home indicator, and the rounded corners land on the display's own
                // corners. A plain `clipShape` would cut the screen back to the safe area.
                .mask {
                    shape.ignoresSafeArea()
                }
                .transition(.opacity)
            }

            // Pinned top-leading in the safe area on every native screen, above the content and never part of
            // its flow. On the web UI the frontend's own header button is the menu button instead (see
            // `KhalaShell.frontendUserScript`): a floating button there would cover its titles and back arrows.
            if shell.destination != .dashboards {
                KhalaGlassButton(symbol: .sidebarLeft, accessibilityLabel: KhalaText.openMenu) {
                    settle(open: true)
                }
                .padding(.leading, Self.menuButtonInset.leading)
                .padding(.top, Self.menuButtonInset.top)
                .transition(.opacity)
            }

            // One gesture layer for the whole drawer, so a drag never loses its view mid-way: a thin leading-edge
            // strip while closed, the whole card while open (tap or drag to close). On a working web UI the web
            // view owns its edges (the app's edge swipe reaches the menu through the frontend); while the
            // frontend is loading or offline the strip stands in.
            Color.clear
                .contentShape(Rectangle())
                .frame(width: shell.isMenuOpen ? nil : CGFloat(KhalaDrawerMath.edgeWidth))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .ignoresSafeArea()
                .allowsHitTesting(
                    shell.isMenuOpen || shell.destination != .dashboards || !shell.isFrontendReady
                )
                .onTapGesture {
                    if shell.isMenuOpen { settle(open: false) }
                }
                .gesture(drawerDrag(sign: sign))
                .accessibilityHidden(!shell.isMenuOpen)
                .accessibilityLabel(KhalaText.closeMenu)
                .accessibilityAddTraits(.isButton)
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
                onMenu: { settle(open: true) },
                onSearch: {
                    settle(open: true)
                    searchFocusRequest += 1
                },
                onItem: { handle($0) },
                onDevice: { device in shell.route(KhalaRouting.target(for: device, cameras: home.cameras)) }
            )
        case .cameras:
            KhalaCamerasView(
                cameras: home.cameras,
                live: home.live,
                actions: KhalaScreenActions(server: server),
                now: home.now,
                calendar: home.calendar,
                onMenu: { settle(open: true) },
                onCamera: { entityId in shell.show(.camera(entityId: entityId)) }
            )
        case .automations:
            KhalaPlaceholderView(
                title: KhalaText.automations,
                message: KhalaText.automationsPending,
                actionTitle: KhalaText.openAutomations,
                onMenu: { settle(open: true) },
                action: { shell.openWebPath("/config/automation/dashboard") }
            )
        case .dashboards:
            EmptyView()
        case .camera, .device, .entity:
            KhalaDetailScreen(destination: shell.destination, server: server, home: home, live: home.live, shell: shell)
        }
    }

    // MARK: - Actions

    private func handle(_ item: KhalaTimelineItem) {
        switch item.kind {
        case let .detection(eventEntityId, cameraEntityId):
            route(entityId: cameraEntityId ?? eventEntityId)
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

    private var settleAnimation: Animation {
        let points = KhalaDrawerMath.settleControlPoints
        return reduceMotion
            ? .easeInOut(duration: 0.2)
            : .timingCurve(points.x1, points.y1, points.x2, points.y2, duration: KhalaDrawerMath.settleDuration)
    }

    private func settle(open: Bool) {
        if open != shell.isMenuOpen {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        withAnimation(settleAnimation) {
            shell.isMenuOpen = open
            dragTravel = 0
        }
        isDragging = false
    }

    private func drawerDrag(sign: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    // Only a mostly horizontal drag is the drawer's; vertical ones belong to the content.
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    isDragging = true
                }
                dragTravel = value.translation.width * sign
            }
            .onEnded { value in
                guard isDragging else { return }
                settle(open: KhalaDrawerMath.opensAfterRelease(
                    wasOpen: shell.isMenuOpen,
                    travel: Double(value.translation.width * sign),
                    projectedTravel: Double(value.predictedEndTranslation.width * sign)
                ))
            }
    }
}
