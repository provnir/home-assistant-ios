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
        self.isEnabled = !Current.isCatalyst && !Current.kiosk.settings.enabled
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
                            shell.openMoreInfo(entityId: device.primaryEntityId)
                        }
                    },
                    onEditDevices: { showsDeviceSettings = true },
                    onSettings: {
                        settle(open: false)
                        appSettings?.presentSettings()
                    }
                )
                .frame(width: openWidth)
                .accessibilityHidden(!shell.isMenuOpen)

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

                ZStack(alignment: .topLeading) {
                    frontend
                        .accessibilityHidden(shell.destination != .dashboards)

                    if shell.destination != .dashboards {
                        ZStack {
                            KhalaGround()
                                .clipShape(cardShape)
                            nativeContent
                        }
                        .transition(.opacity)
                    }

                    if shell.destination == .dashboards, !shell.isMenuOpen {
                        // The way back from the web UI: the web view owns its own edge swipes, so a button.
                        KhalaGlassButton(symbol: .sidebarLeft, accessibilityLabel: KhalaText.openMenu) {
                            settle(open: true)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 16)
                        .padding(.bottom, NativeTabBarState.shared.isEnabled ? 72 : 16)
                        .transition(.opacity)
                    }

                    // One gesture layer for the whole drawer, so a drag never loses its view mid-way: a thin
                    // leading-edge strip while closed, the whole card while open (tap or drag to close).
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: shell.isMenuOpen ? nil : CGFloat(KhalaDrawerMath.edgeWidth))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .ignoresSafeArea()
                        .allowsHitTesting(shell.isMenuOpen || shell.destination != .dashboards)
                        .onTapGesture {
                            if shell.isMenuOpen { settle(open: false) }
                        }
                        .gesture(drawerDrag(sign: sign))
                        .accessibilityHidden(!shell.isMenuOpen)
                        .accessibilityLabel(KhalaText.closeMenu)
                        .accessibilityAddTraits(.isButton)
                }
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
        .sheet(isPresented: $showsDeviceSettings) {
            KhalaDeviceSettingsView(
                serverId: server.identifier.rawValue,
                entityNames: home.entityNames,
                assignments: home.assignments,
                onSave: { home.setAssignments($0) }
            )
        }
    }

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
                onDevice: { device in shell.openMoreInfo(entityId: device.primaryEntityId) }
            )
        case .cameras:
            KhalaCamerasView(
                cameras: home.cameras,
                onMenu: { settle(open: true) },
                onCamera: { camera in shell.openCamera(entityId: camera.entityId, name: camera.name) }
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
        }
    }

    // MARK: - Actions

    private func handle(_ item: KhalaTimelineItem) {
        switch item.kind {
        case let .detection(eventEntityId, cameraEntityId):
            if let cameraEntityId {
                let name = home.cameras.first { $0.entityId == cameraEntityId }?.name
                shell.openCamera(entityId: cameraEntityId, name: name)
            } else {
                shell.openMoreInfo(entityId: eventEntityId)
            }
        case .scheduled, .timestamp:
            if let target = item.targetEntityId {
                shell.openMoreInfo(entityId: target)
            }
        case .sunrise, .sunset, .now:
            break
        }
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
