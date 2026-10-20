import Foundation

/// What the web frontend is showing, as Khala's frontend script (`KhalaFrontendScript`) reports it whenever it
/// changes: the page's path, the dialog on top (the frontend's dialog manager keeps its tag in `history.state`),
/// the dashboard on screen, and that dashboard's own actions.
struct KhalaFrontendState: Hashable {
    let path: String
    let dialog: String?
    let dashboard: KhalaDashboardPage?
    let actions: [KhalaFrontendAction]

    init(path: String, dialog: String? = nil, dashboard: KhalaDashboardPage? = nil, actions: [KhalaFrontendAction] = []) {
        self.path = path
        self.dialog = dialog
        self.dashboard = dashboard
        self.actions = actions
    }

    /// Reads the script's `state` message. Anything malformed reads as nil (the shell then behaves as if the
    /// script were absent: no views menu, frontend header left alone).
    init?(json: Any?) {
        guard let json = json as? [String: Any], let path = KhalaValue.string(json["path"]) else { return nil }
        self.init(
            path: path,
            dialog: KhalaValue.string(json["dialog"]),
            dashboard: KhalaDashboardPage(json: json["dashboard"]),
            actions: (json["actions"] as? [Any] ?? []).compactMap(KhalaFrontendAction.init(json:))
        )
    }
}
