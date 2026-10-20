import Foundation

/// One of the user's dashboards as the drawer's DASHBOARDS section and the dashboards header list it: a frontend
/// panel from Home Assistant's own sidebar (Lovelace dashboards, the built-in Home/Energy/Map/History/... panels
/// and add-on panels), in the sidebar's order with the user's hidden panels left out. `id` is the panel's
/// `url_path` (`lovelace`, `energy`, `dashboard-kitchen`), so the panel's page is `/<id>`.
struct KhalaDashboard: Hashable, Identifiable {
    let id: String
    let title: String

    /// The frontend path that opens the dashboard on its default view.
    var path: String { "/" + id }

    /// Dashboards whose title contains `query` (the drawer's search); all of them for an empty query.
    static func matching(_ query: String, in dashboards: [KhalaDashboard]) -> [KhalaDashboard] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return dashboards }
        return dashboards.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}
