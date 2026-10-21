import Foundation

/// What Khala's header shows over a Home Assistant page whose own chrome the frontend script lifted
/// (`KhalaPageChrome`): one leading control (Back, or the shell's menu button on a top-level page), the page's
/// title in the large-title style, its search as a glass field, its tabs as bottom glass sub-tabs, its "+" and
/// its other tools top-right (mockup `DaySettingsPage`). Pure, so every rule is tested on Linux;
/// `KhalaPageHeaderView` draws it.
struct KhalaPageHeader: Equatable {
    /// Where the header's Back goes.
    enum Back: Equatable {
        /// No Back: a top-level page (History, Logbook) keeps the shell's menu button.
        case none
        /// The frontend's own back handling (`KhalaFrontendScript` back): closes a dialog, or the frontend's
        /// back arrow with its back path and unsaved-changes guards.
        case frontend
        /// The native Settings screen: a settings section's own page, which the frontend would leave for its
        /// settings dashboard (`/config`), the page Khala's Settings stands in for.
        case settings
    }

    /// The row of glass buttons (9 + 44 + 9), as over a dashboard.
    static let rowHeight: Double = KhalaFrontendScript.headerInset
    /// The large title's block: a 41 pt line and 7 pt below it.
    static let titleHeight: Double = 41 + 7
    /// The search field's block: 44 pt and 15 pt below it (mockup: content starts 16 pt under the field).
    static let searchHeight: Double = 44 + 15

    let title: String
    let back: Back
    /// The large title and the search field show: not while a dialog is up (only the row stays).
    let showsTitle: Bool
    let search: KhalaPageSearch?
    /// Two or more, else none (one tab is just the page).
    let tabs: [KhalaPageTab]
    let primary: KhalaFrontendAction?
    /// The toolbar's other tools for the "More" menu, in sections: each of the frontend's menus is one (their
    /// trigger is a generic "Menu" button, so its title is dropped), and buttons next to each other share one.
    let toolSections: [[KhalaFrontendAction]]
    let titleMenu: [KhalaFrontendAction]

    /// How far below the safe area the page's content starts; `KhalaFrontendScript` sets the same inset.
    var height: Double {
        Self.height(showsTitle: showsTitle, hasSearch: search != nil)
    }

    static func height(showsTitle: Bool, hasSearch: Bool) -> Double {
        guard showsTitle else { return rowHeight }
        return rowHeight + titleHeight + (hasSearch ? searchHeight : 0)
    }

    /// Nil unless the frontend script lifted the page's chrome (then the dashboards header, with the frontend's
    /// own toolbar under it, is the one to draw).
    /// - Parameters:
    ///   - settingsEntryPath: the page the native Settings screen opened last, whose Back returns there.
    init?(
        path: String?,
        state: KhalaFrontendState?,
        isMoreInfoOpen: Bool,
        settingsEntryPath: String?,
        fallbackTitle: String
    ) {
        guard let state, let page = state.page, page.isLifted else { return nil }
        // The report must be about the page on screen (it can trail a navigation by a moment).
        if let path, KhalaFrontendPath.panelId(path) != KhalaFrontendPath.panelId(state.path) { return nil }

        let isDialogOpen = state.dialog != nil || isMoreInfoOpen
        let tabs = page.tabs.count > 1 ? page.tabs : []

        if !tabs.isEmpty, let section = KhalaSettingsCatalog.section(forTabPaths: tabs.map(\.path)) {
            title = section.title
        } else {
            title = page.title ?? tabs.first(where: \.isActive)?.title ?? fallbackTitle
        }

        if isDialogOpen {
            back = .frontend
        } else if KhalaSettingsCatalog.backLeadsToSettings(path: state.path, entryPath: settingsEntryPath) {
            back = .settings
        } else {
            back = page.hasBack ? .frontend : .none
        }

        showsTitle = !isDialogOpen
        search = isDialogOpen ? nil : page.search
        self.tabs = isDialogOpen ? [] : tabs
        primary = isDialogOpen ? nil : page.primary
        toolSections = isDialogOpen ? [] : Self.sections(of: page.tools)
        titleMenu = isDialogOpen ? [] : page.titleMenu
    }

    /// Menus become sections of their own; runs of plain buttons share one.
    static func sections(of tools: [KhalaFrontendAction]) -> [[KhalaFrontendAction]] {
        var sections: [[KhalaFrontendAction]] = []
        var buttons: [KhalaFrontendAction] = []
        for tool in tools {
            if tool.children.isEmpty {
                buttons.append(tool)
            } else {
                if !buttons.isEmpty { sections.append(buttons) }
                buttons = []
                sections.append(tool.children)
            }
        }
        if !buttons.isEmpty { sections.append(buttons) }
        return sections
    }

    /// The tab on screen, for the sub-tab bar's selection.
    var activeTabIndex: Int {
        tabs.firstIndex(where: \.isActive) ?? 0
    }
}
