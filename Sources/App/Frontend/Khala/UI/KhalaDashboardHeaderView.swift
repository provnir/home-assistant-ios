import SFSafeSymbols
import Shared
import SwiftUI

/// Khala's header over the web frontend (Dashboards): a soft material band behind the status bar and the row,
/// which the web content scrolls under, and floating glass controls on it — one leading control (the shell's
/// pinned menu button, drawn by `KhalaShellView`, or Back in its place while the frontend is on a sub-view, a
/// dialog or a sub-page), the dashboard's name as a pull-down menu (its views, then all dashboards: vertical
/// lists, never side-scrolling), and the dashboard's own actions under "More". The frontend's own toolbar is
/// hidden on dashboards (`KhalaFrontendScript`), and its content starts below this row
/// (`KhalaFrontendScript.headerInset`).
struct KhalaDashboardHeaderView: View {
    let header: KhalaDashboardHeader
    let icons: [String: FrontendIcon]
    let onBack: () -> Void
    let onDashboard: (KhalaDashboard) -> Void
    let onView: (KhalaDashboardView, String) -> Void
    let onAction: (KhalaFrontendAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            // One leading control, never two: Back while the frontend is on a sub-page or dialog, otherwise the
            // shell's pinned menu button, which sits in this slot.
            if header.showsBack {
                KhalaGlassButton(symbol: .chevronLeft, accessibilityLabel: KhalaScreenText.back, action: onBack)
                    .transition(.opacity)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            titleMenu
                .layoutPriority(1)
            Spacer(minLength: 0)
            if !header.actions.isEmpty {
                actionsMenu
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .frame(height: CGFloat(KhalaFrontendScript.headerInset), alignment: .top)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(alignment: .top) { backdrop }
        .animation(.easeOut(duration: 0.2), value: header.showsBack)
        .animation(.easeOut(duration: 0.2), value: header.actions.isEmpty)
    }

    // MARK: - Backdrop

    /// From the display's top edge (behind the status bar) to a little below the row: the material at full
    /// strength over the status bar and the row, fading out below it, so content scrolled under reads as under
    /// glass and the status bar's ink stays legible. It takes the row's touches (as a navigation bar does) but not
    /// the fade's.
    private var backdrop: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: Self.fade)
                    .mask {
                        LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    }
            }
            .padding(.bottom, -Self.fade)
            .allowsHitTesting(false)
            Color.clear
                .contentShape(Rectangle())
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityHidden(true)
    }

    /// How far below the row the backdrop fades out.
    private static let fade: CGFloat = 18

    // MARK: - Title menu

    private var titleMenu: some View {
        Menu {
            if !header.views.isEmpty, let prefix = header.viewPrefix {
                Section(KhalaText.views) {
                    Picker(KhalaText.views, selection: Binding<Int?>(
                        get: { header.views.first(where: \.isCurrent)?.view.index },
                        set: { index in
                            guard let item = header.views.first(where: { $0.view.index == index }) else { return }
                            onView(item.view, prefix)
                        }
                    )) {
                        ForEach(header.views) { item in
                            Text(item.title).tag(Optional(item.view.index))
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            if !header.dashboards.isEmpty {
                Section(KhalaText.dashboards) {
                    Picker(KhalaText.dashboards, selection: Binding<String?>(
                        get: { header.current?.id },
                        set: { id in
                            guard let dashboard = header.dashboards.first(where: { $0.id == id }) else { return }
                            onDashboard(dashboard)
                        }
                    )) {
                        ForEach(header.dashboards) { dashboard in
                            Label {
                                Text(dashboard.title)
                            } icon: {
                                icon(for: dashboard)
                            }
                            .tag(Optional(dashboard.id))
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(header.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KhalaTheme.ink)
                        .lineLimit(1)
                    if let subtitle = header.subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(KhalaTheme.secondary)
                            .lineLimit(1)
                    }
                }
                Image(systemSymbol: .chevronDown)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(KhalaTheme.secondary)
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(height: 44)
            .khalaGlass(in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel([header.title, header.subtitle].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(KhalaText.chooseDashboard)
    }

    private func icon(for dashboard: KhalaDashboard) -> Image {
        let icon = icons[dashboard.id] ?? .material(.viewDashboardIcon)
        return Image(uiImage: icon.image(ofSize: CGSize(width: 24, height: 24), color: .label))
            .renderingMode(.template)
    }

    // MARK: - Actions

    private var actionsMenu: some View {
        Menu {
            ForEach(header.actions) { action in
                if action.children.isEmpty {
                    actionButton(action)
                } else {
                    Menu {
                        ForEach(action.children) { child in
                            actionButton(child)
                        }
                    } label: {
                        actionLabel(action)
                    }
                }
            }
        } label: {
            Image(systemSymbol: .ellipsis)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(KhalaTheme.ink)
                .frame(width: 44, height: 44)
                .khalaGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(KhalaScreenText.more)
    }

    private func actionButton(_ action: KhalaFrontendAction) -> some View {
        Button {
            onAction(action)
        } label: {
            actionLabel(action)
        }
    }

    @ViewBuilder
    private func actionLabel(_ action: KhalaFrontendAction) -> some View {
        if let symbol = symbol(for: action.glyph) {
            Label(action.title, systemSymbol: symbol)
        } else {
            Text(action.title)
        }
    }

    private func symbol(for glyph: KhalaFrontendAction.Glyph?) -> SFSymbol? {
        switch glyph {
        case .search: return .magnifyingglass
        case .assist: return .bubbleLeftAndBubbleRight
        case .add: return .plus
        case .edit: return .pencil
        case .refresh: return .arrowClockwise
        case .list: return .listBullet
        case .device: return .externaldrive
        case .automation: return .gearshape2
        case .area: return .squareSplit2x2
        case .person: return .person
        case nil: return nil
        }
    }
}

#Preview {
    let dashboards = [
        KhalaDashboard(id: "home", title: "Overview"),
        KhalaDashboard(id: "dashboard-den", title: "Den"),
        KhalaDashboard(id: "energy", title: "Energy"),
    ]
    let state = KhalaFrontendState(
        path: "/dashboard-den/lights",
        dashboard: KhalaDashboardPage(
            prefix: "/dashboard-den",
            views: [
                KhalaDashboardView(index: 0, path: "main", title: "Main", icon: nil),
                KhalaDashboardView(index: 1, path: "lights", title: "Lights", icon: nil),
            ],
            currentViewIndex: 1
        ),
        actions: [KhalaFrontendAction(id: "a0", title: "Search", key: "ui.panel.lovelace.menu.search_home_assistant")]
    )
    ZStack(alignment: .top) {
        KhalaGround()
        KhalaDashboardHeaderView(
            header: KhalaDashboardHeader(
                dashboards: dashboards,
                path: state.path,
                state: state,
                isMoreInfoOpen: false,
                fallbackTitle: KhalaText.dashboards
            ),
            icons: [:],
            onBack: {},
            onDashboard: { _ in },
            onView: { _, _ in },
            onAction: { _ in }
        )
    }
}
