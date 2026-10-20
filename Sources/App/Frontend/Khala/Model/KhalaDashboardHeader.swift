import Foundation

/// What the native header over the web frontend shows (Dashboards destination): the dashboard's name as a
/// pull-down of the user's dashboards, the current dashboard's views in the same menu, a back button while the
/// frontend is on a sub-view, a dialog or a page that is not one of the dashboards, and the dashboard's own
/// actions. Pure, so every rule is tested on Linux; `KhalaDashboardHeaderView` draws it.
struct KhalaDashboardHeader: Equatable {
    struct ViewItem: Equatable, Identifiable {
        let view: KhalaDashboardView
        let title: String
        let isCurrent: Bool
        var id: Int { view.index }
    }

    /// The dashboard on screen, nil on a page that isn't one of them (`/config/...`, `/profile`).
    let current: KhalaDashboard?
    /// The menu's label: the dashboard's name.
    let title: String
    /// Under the name: the view on screen, when there is a choice of views or it is a sub-view.
    let subtitle: String?
    /// The current dashboard's selectable views; empty when it has one view (nothing to choose) or the frontend
    /// script couldn't read them.
    let views: [ViewItem]
    /// Where the view selection goes: the dashboard's route prefix.
    let viewPrefix: String?
    let dashboards: [KhalaDashboard]
    let showsBack: Bool
    /// The dashboard's own actions ("More" menu); only while the frontend's toolbar is hidden, since otherwise
    /// it shows them itself.
    let actions: [KhalaFrontendAction]

    /// - Parameters:
    ///   - path: the frontend page on screen (the app's URL observation, `WebFrontendOverlayState.currentPath`).
    ///   - state: the frontend script's last report, if any; fresher than `path` and the only source of views.
    ///   - isMoreInfoOpen: the frontend's `more_info/opened` external-bus report.
    ///   - fallbackTitle: the label when the page isn't a listed dashboard.
    init(
        dashboards: [KhalaDashboard],
        path: String?,
        state: KhalaFrontendState?,
        isMoreInfoOpen: Bool,
        fallbackTitle: String
    ) {
        let path = state?.path ?? path
        let current = KhalaFrontendPath.dashboard(for: path, in: dashboards)
        // The script's dashboard report only counts when it is about the page on screen (it can trail a
        // navigation by a moment).
        let page = state?.dashboard.flatMap { page -> KhalaDashboardPage? in
            guard let path else { return page }
            let panel = KhalaFrontendPath.panelId(path)
            return panel == nil || panel == page.panelId ? page : nil
        }

        self.current = current
        self.dashboards = dashboards
        self.title = current?.title ?? fallbackTitle

        let selectable = (page?.isHeaderHidden == true && page?.isEditMode == false) ? page?.views ?? [] : []
        let names = selectable.map { view in
            view.title ?? page?.unnamedViewTitle ?? KhalaText.view(number: view.index + 1)
        }
        if selectable.count > 1 {
            self.views = zip(selectable, names).map { view, name in
                ViewItem(view: view, title: name, isCurrent: view.index == page?.currentViewIndex)
            }
            viewPrefix = page?.prefix
        } else {
            self.views = []
            viewPrefix = nil
        }

        if let page, page.isSubview {
            subtitle = page.subviewTitle
        } else {
            subtitle = views.first(where: \.isCurrent)?.title
        }

        let isDialogOpen = state?.dialog != nil || isMoreInfoOpen
        // Until the dashboards list has loaded, nothing is "off" a dashboard.
        let isOffDashboard = current == nil && path != nil && !dashboards.isEmpty
        showsBack = isDialogOpen || page?.isSubview == true || page?.hasBackButton == true || isOffDashboard

        actions = (page?.isHeaderHidden == true && page?.isEditMode == false) ? state?.actions ?? [] : []
    }
}
