import Foundation

/// The page chrome of a Home Assistant page that isn't a dashboard, as `KhalaFrontendScript` reports it: the
/// frontend's own `hass-subpage`, `hass-tabs-subpage` (also inside `hass-tabs-subpage-data-table`) or
/// `ha-top-app-bar-fixed` (History, Logbook, To-do, Media, ...) toolbar, which the script hides ("lifts") so Khala's
/// header draws it instead: title, back, search, tabs, primary action, tools.
struct KhalaPageChrome: Hashable {
    enum Kind: String, Hashable {
        case subpage
        case tabs
        case appBar = "appbar"
    }

    let kind: Kind
    /// The frontend's toolbar is hidden and Khala's header stands in for it. False when lifting failed or the
    /// page is in a mode only the frontend's toolbar handles (selection mode, an editor with a close button);
    /// the frontend's toolbar then shows under Khala's slim header.
    let isLifted: Bool
    let title: String?
    /// The page has the frontend's back arrow (a sub-page), as opposed to its menu button (a top-level page).
    let hasBack: Bool
    let tabs: [KhalaPageTab]
    let search: KhalaPageSearch?
    /// The page's "+" (its add FAB), performed through the frontend's own handler.
    let primary: KhalaFrontendAction?
    /// The toolbar's other buttons and menus.
    let tools: [KhalaFrontendAction]
    /// A title that is itself a menu (To-do's list picker).
    let titleMenu: [KhalaFrontendAction]

    init(
        kind: Kind,
        isLifted: Bool = true,
        title: String? = nil,
        hasBack: Bool = false,
        tabs: [KhalaPageTab] = [],
        search: KhalaPageSearch? = nil,
        primary: KhalaFrontendAction? = nil,
        tools: [KhalaFrontendAction] = [],
        titleMenu: [KhalaFrontendAction] = []
    ) {
        self.kind = kind
        self.isLifted = isLifted
        self.title = title
        self.hasBack = hasBack
        self.tabs = tabs
        self.search = search
        self.primary = primary
        self.tools = tools
        self.titleMenu = titleMenu
    }

    init?(json: Any?) {
        guard let json = json as? [String: Any], let kind = KhalaValue.string(json["kind"]).flatMap(Kind.init) else {
            return nil
        }
        self.init(
            kind: kind,
            isLifted: KhalaValue.bool(json["lifted"]) ?? false,
            title: KhalaValue.string(json["title"]),
            hasBack: KhalaValue.bool(json["back"]) ?? false,
            tabs: KhalaValue.list(json["tabs"]).compactMap(KhalaPageTab.init(json:)),
            search: KhalaPageSearch(json: json["search"]),
            primary: KhalaFrontendAction(json: json["primary"]),
            tools: KhalaValue.list(json["tools"]).compactMap(KhalaFrontendAction.init(json:)),
            titleMenu: KhalaValue.list(json["titleMenu"]).compactMap(KhalaFrontendAction.init(json:))
        )
    }
}
