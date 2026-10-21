import SFSafeSymbols
import Shared
import SwiftUI

/// Khala's chrome over a Home Assistant page whose own toolbar the frontend script lifted (mockup
/// `DaySettingsPage`): one leading control (Back, or the shell's pinned menu button on a top-level page), the
/// page's "+" and its other tools ("More") top-right as glass buttons, the page's title in the large-title style
/// (a pull-down when the frontend's title is a menu, To-do's lists), the page's search as a glass field that
/// types into the page's own, and its tabs as the bottom glass sub-tabs. The page's content starts below this
/// header (`KhalaPageHeader.height`, the same inset the script gives the frontend).
struct KhalaPageHeaderView: View {
    let header: KhalaPageHeader
    /// The page on screen; a new one resets the search field to the page's own value.
    let pageId: String
    let onBack: () -> Void
    let onAction: (KhalaFrontendAction) -> Void
    let onSearch: (String) -> Void
    let onTab: (KhalaPageTab) -> Void

    @State private var query = ""
    @State private var tabSelection = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                row
                    .frame(height: CGFloat(KhalaPageHeader.rowHeight), alignment: .top)
                if header.showsTitle {
                    title
                        .frame(height: 41)
                        .padding(.horizontal, 20)
                        .padding(.bottom, CGFloat(KhalaPageHeader.titleHeight) - 41)
                        .transition(.opacity)
                    if header.search != nil {
                        searchField
                            .padding(.horizontal, 16)
                            .padding(.bottom, CGFloat(KhalaPageHeader.searchHeight) - 44)
                            .transition(.opacity)
                    }
                }
            }
            .frame(height: CGFloat(header.height), alignment: .top)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(alignment: .top) { backdrop }

            if header.tabs.count > 1 {
                KhalaSubTabBar(tabs: subTabs, selection: tabBinding, accent: KhalaTheme.accent(.security))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: header.showsTitle)
        .animation(.easeOut(duration: 0.2), value: header.back)
        .onAppear { syncFromPage() }
        .onChange(of: pageId) { _ in syncFromPage() }
        .onChange(of: header.activeTabIndex) { index in
            if index != tabSelection { tabSelection = index }
        }
    }

    private func syncFromPage() {
        query = header.search?.value ?? ""
        tabSelection = header.activeTabIndex
    }

    // MARK: - Row

    private var row: some View {
        HStack(spacing: 8) {
            // One leading control, never two: Back here, or the shell's pinned menu button in this slot.
            if header.back != .none {
                KhalaGlassButton(symbol: .chevronLeft, accessibilityLabel: KhalaScreenText.back, action: onBack)
                    .transition(.opacity)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer(minLength: 0)
            if !header.toolSections.isEmpty {
                toolsMenu
            }
            if let primary = header.primary {
                KhalaGlassButton(symbol: .plus, accessibilityLabel: primary.title) {
                    onAction(primary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
    }

    private var toolsMenu: some View {
        Menu {
            ForEach(Array(header.toolSections.enumerated()), id: \.offset) { _, section in
                Section {
                    ForEach(section) { tool in
                        Button {
                            onAction(tool)
                        } label: {
                            if tool.isChecked == true {
                                Label(tool.title, systemSymbol: .checkmark)
                            } else {
                                Text(tool.title)
                            }
                        }
                        .disabled(tool.isDisabled)
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
        .accessibilityLabel(KhalaText.more)
    }

    // MARK: - Title

    @ViewBuilder
    private var title: some View {
        if header.titleMenu.isEmpty {
            titleText
                .accessibilityAddTraits(.isHeader)
        } else {
            Menu {
                ForEach(header.titleMenu) { item in
                    Button {
                        onAction(item)
                    } label: {
                        Text(item.title)
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    titleText
                    Image(systemSymbol: .chevronDown)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(KhalaTheme.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var titleText: some View {
        Text(header.title)
            .font(KhalaTheme.largeTitle)
            .kerning(0.3)
            .foregroundStyle(KhalaTheme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemSymbol: .magnifyingglass)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KhalaTheme.tertiary)
            TextField(header.search?.placeholder ?? KhalaText.search, text: $query)
                .font(.system(size: 16))
                .foregroundStyle(KhalaTheme.ink)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onChange(of: query) { text in
                    // Only what the person types goes to the page (not a sync from the page's own value).
                    if text != header.search?.value { onSearch(text) }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemSymbol: .xmarkCircleFill)
                        .foregroundStyle(KhalaTheme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KhalaScreenText.close)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .khalaGlass(in: Capsule(), interactive: true)
    }

    // MARK: - Tabs

    private var subTabs: [KhalaSubTab] {
        header.tabs.map { KhalaSubTab(title: $0.title, symbol: KhalaSettingsSymbols.symbol($0.glyph)) }
    }

    private var tabBinding: Binding<Int> {
        Binding(
            get: { tabSelection },
            set: { index in
                tabSelection = index
                guard header.tabs.indices.contains(index) else { return }
                onTab(header.tabs[index])
            }
        )
    }

    // MARK: - Backdrop

    /// As over a dashboard (`KhalaDashboardHeaderView`): the material from the display's top edge through the
    /// header, fading out just below it; it takes the header's touches, not the fade's.
    private var backdrop: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: 18)
                    .mask {
                        LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    }
            }
            .padding(.bottom, -18)
            .allowsHitTesting(false)
            Color.clear
                .contentShape(Rectangle())
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityHidden(true)
    }
}

#Preview {
    let state = KhalaFrontendState(
        path: "/config/devices/dashboard",
        page: KhalaPageChrome(
            kind: .tabs,
            title: "Devices",
            hasBack: true,
            tabs: [
                KhalaPageTab(path: "/config/integrations", title: "Integrations", isActive: false),
                KhalaPageTab(path: "/config/devices", title: "Devices", isActive: true),
                KhalaPageTab(path: "/config/entities", title: "Entities", isActive: false),
                KhalaPageTab(path: "/config/helpers", title: "Helpers", isActive: false),
            ],
            search: KhalaPageSearch(placeholder: "Search devices"),
            primary: KhalaFrontendAction(id: "p1", title: "Add device")
        )
    )
    ZStack {
        KhalaGround()
        if let header = KhalaPageHeader(
            path: state.path, state: state, isMoreInfoOpen: false, settingsEntryPath: nil, fallbackTitle: "Settings"
        ) {
            KhalaPageHeaderView(
                header: header,
                pageId: state.path,
                onBack: {},
                onAction: { _ in },
                onSearch: { _ in },
                onTab: { _ in }
            )
        }
    }
}
