import Foundation
import Shared

/// The Settings destination and the Home Assistant pages it opens: those show in the web UI under Khala's page
/// chrome (`KhalaPageHeader`, the frontend's own toolbar lifted by `KhalaFrontendScript`), and their Back returns
/// to the native Settings screen where the frontend's would go to its own settings dashboard.
extension KhalaShellModel {
    /// Khala's header over a page whose chrome the frontend script lifted; nil over a dashboard, or where the
    /// page keeps its own toolbar (then `dashboardHeader` is drawn).
    var pageHeader: KhalaPageHeader? {
        guard destination == .dashboards else { return nil }
        let fresh = KhalaPageHeader(
            path: frontendPath,
            state: frontendState,
            isMoreInfoOpen: isMoreInfoOpen,
            settingsEntryPath: settingsEntryPath,
            fallbackTitle: KhalaText.serverSettings
        )
        guard let pageTabHold else { return fresh }
        return pageTabHold.header(fresh: fresh, now: Current.date())
    }

    /// The drawer's Settings row is lit on the Settings screen and on Home Assistant's settings pages.
    var isSettingsHighlighted: Bool {
        if destination == .settings { return true }
        guard destination == .dashboards, let serverSettings else { return false }
        return highlightedDashboardId == serverSettings.id
    }

    /// Opens one of Home Assistant's settings pages (a section, a search result, the server card's target) in
    /// the web UI; Back on it returns here.
    func openServerPage(_ path: String) {
        settingsRequestedPath = path
        settingsEntryPath = path
        settingsLandingDeadline = Current.date().addingTimeInterval(3)
        openWebPath(path)
    }

    /// The page header's Back.
    func goBackFromPage() {
        pageTabHold = nil
        guard let header = pageHeader else {
            goBackInFrontend()
            return
        }
        switch header.back {
        case .settings:
            returnToSettings()
        case .frontend:
            goBackInFrontend()
        case .none:
            break
        }
    }

    /// Back to the Settings screen. The web UI underneath goes back to the last dashboard, so the Dashboards
    /// destination shows a dashboard again rather than the settings page just left.
    func returnToSettings() {
        settingsEntryPath = nil
        settingsRequestedPath = nil
        settingsLandingDeadline = nil
        show(.settings)
        if let dashboard = dashboards.first(where: { $0.id == lastDashboardId }) ?? dashboards.first {
            webViewController?.openSidebarPath(dashboard.path)
        }
    }

    /// Types into the lifted page's own search field.
    func searchPage(_ text: String) {
        webViewController?.evaluateJavaScript(KhalaFrontendScript.searchCall(text)) { result, _ in
            if result as? Bool != true {
                Current.Log.warning("Khala: page search did not reach the page")
            }
        }
    }

    /// Opens one of the lifted page's tabs through the page's own tab link (it replaces the history entry, as
    /// the frontend's tabs do), else by navigating there.
    func openPageTab(_ tab: KhalaPageTab) {
        // Keep the chrome (and the tab bar, whose lens is moving to this tab) up while the frontend swaps pages.
        let hold = KhalaPageTabHold(header: pageHeader, selecting: tab.path, now: Current.date())
        pageTabHold = hold
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((KhalaPageTabHold.duration + 0.1) * 1_000_000_000))
            if let self, pageTabHold == hold { pageTabHold = nil }
        }
        webViewController?.evaluateJavaScript(KhalaFrontendScript.tabCall(path: tab.path)) { [weak self] result, _ in
            guard result as? Bool != true else { return }
            Task { @MainActor in self?.webViewController?.openSidebarPath(tab.path) }
        }
    }

    /// Called whenever the frontend's page changes: follows the frontend's redirect of a page Settings opened
    /// (`/config/tools` → `/config/tools/yaml`), and shows the native Settings screen in place of the frontend's
    /// own settings dashboard (`/config`), wherever the frontend went there from (its back arrow, a link).
    func frontendPageChanged() {
        guard let path = frontendState?.path ?? frontendPath else { return }
        if let requested = settingsRequestedPath, let deadline = settingsLandingDeadline, Current.date() < deadline,
           KhalaSettingsCatalog.isLanding(path, of: requested), settingsEntryPath != path {
            settingsEntryPath = path
        }
        if destination == .dashboards, isFrontendReady, KhalaSettingsCatalog.isSettingsHome(path) {
            returnToSettings()
        }
    }
}
