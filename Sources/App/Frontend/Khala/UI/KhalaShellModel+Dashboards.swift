import Foundation
import Shared

/// The Dashboards destination: the web frontend under Khala's own header. Navigation goes through the frontend's
/// external-bus `navigate` command (`WebViewController.openSidebarPath`, the App Labs tab bar's path); back and the
/// dashboard's own actions go through `KhalaFrontendScript`.
extension KhalaShellModel {
    /// What the native header shows right now.
    var dashboardHeader: KhalaDashboardHeader {
        KhalaDashboardHeader(
            dashboards: dashboards,
            otherPages: serverSettings.map { [$0] } ?? [],
            path: frontendPath,
            state: frontendState,
            isMoreInfoOpen: isMoreInfoOpen,
            fallbackTitle: KhalaText.dashboards
        )
    }

    /// The listed page on screen while the web UI is: a DASHBOARDS row, or Home Assistant's settings panel (which
    /// lights the drawer's Settings row, `isSettingsHighlighted`).
    var highlightedDashboardId: String? {
        destination == .dashboards ? dashboardHeader.currentPage?.id : nil
    }

    /// Opens a dashboard (its default view) in the web UI.
    func openDashboard(_ dashboard: KhalaDashboard) {
        settingsEntryPath = nil
        show(.dashboards)
        webViewController?.openSidebarPath(dashboard.path)
    }

    /// Switches the dashboard on screen to one of its views.
    func openView(_ view: KhalaDashboardView, prefix: String) {
        webViewController?.openSidebarPath(KhalaFrontendPath.viewPath(prefix: prefix, view: view))
    }

    /// The header's back button: closes the frontend's dialog, or leaves a sub-view or sub-page through the
    /// frontend's own back arrow. With nothing to go back to, it lands on the last dashboard.
    func goBackInFrontend() {
        guard let webViewController else { return }
        webViewController.evaluateJavaScript(KhalaFrontendScript.backCall) { [weak self] result, _ in
            guard let self, result as? String == "none" else { return }
            Task { @MainActor in self.openLastDashboard() }
        }
    }

    /// Runs one of the dashboard's own actions (search, Assist, edit, ...) through the frontend's handler.
    func perform(_ action: KhalaFrontendAction) {
        webViewController?.evaluateJavaScript(
            KhalaFrontendScript.performCall(actionId: action.id, title: action.title)
        ) { result, _ in
            if result as? Bool != true {
                Current.Log.warning("Khala: dashboard action \(action.title) did not run")
            }
        }
    }

    func openLastDashboard() {
        guard let dashboard = dashboards.first(where: { $0.id == lastDashboardId }) ?? dashboards.first else {
            return
        }
        openDashboard(dashboard)
    }
}
