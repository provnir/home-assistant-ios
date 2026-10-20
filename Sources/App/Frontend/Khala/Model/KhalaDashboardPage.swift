import Foundation

/// The dashboard (`hui-root`) the frontend is showing, as Khala's frontend script reports it.
struct KhalaDashboardPage: Hashable {
    /// The dashboard's route prefix (`/lovelace`, `/dashboard-kitchen`, `/energy`).
    let prefix: String
    let views: [KhalaDashboardView]
    /// Index of the view on screen in the dashboard's `views` (it can be a sub-view, which `views` never lists).
    let currentViewIndex: Int?
    let isSubview: Bool
    let subviewTitle: String?
    /// The page asked for a back button of its own (`?historyBack=1`), like a sub-view.
    let hasBackButton: Bool
    let isEditMode: Bool
    /// The frontend's header is hidden and the native header stands in for it. False when hiding it failed
    /// (a frontend this script doesn't know), in which case the frontend keeps its own header under ours.
    let isHeaderHidden: Bool
    /// The frontend's own word for an untitled view ("Unnamed view"), in the user's language.
    let unnamedViewTitle: String?

    init(
        prefix: String,
        views: [KhalaDashboardView],
        currentViewIndex: Int?,
        isSubview: Bool = false,
        subviewTitle: String? = nil,
        hasBackButton: Bool = false,
        isEditMode: Bool = false,
        isHeaderHidden: Bool = true,
        unnamedViewTitle: String? = nil
    ) {
        self.prefix = prefix
        self.views = views
        self.currentViewIndex = currentViewIndex
        self.isSubview = isSubview
        self.subviewTitle = subviewTitle
        self.hasBackButton = hasBackButton
        self.isEditMode = isEditMode
        self.isHeaderHidden = isHeaderHidden
        self.unnamedViewTitle = unnamedViewTitle
    }

    init?(json: Any?) {
        guard let json = json as? [String: Any], let prefix = KhalaValue.string(json["prefix"]) else { return nil }
        self.init(
            prefix: prefix,
            views: (json["views"] as? [Any] ?? []).compactMap(KhalaDashboardView.init(json:)),
            currentViewIndex: KhalaValue.int(json["current"]),
            isSubview: KhalaValue.bool(json["subview"]) ?? false,
            subviewTitle: KhalaValue.string(json["subviewTitle"]),
            hasBackButton: KhalaValue.bool(json["backButton"]) ?? false,
            isEditMode: KhalaValue.bool(json["editMode"]) ?? false,
            isHeaderHidden: KhalaValue.bool(json["headerHidden"]) ?? false,
            unnamedViewTitle: KhalaValue.string(json["unnamedTitle"])
        )
    }

    /// The panel the dashboard belongs to (`lovelace` for `/lovelace`).
    var panelId: String? { KhalaFrontendPath.panelId(prefix) }
}
