import Foundation

/// Reading the web frontend's paths: `/<panel url_path>/<view or sub-page>…`, the shape the frontend's router uses
/// (`partial-panel-resolver` picks the panel from the first segment; `hui-root` the view from the second).
enum KhalaFrontendPath {
    /// The path's segments, without empty ones, query or fragment. `"/lovelace/kitchen?edit=1"` →
    /// `["lovelace", "kitchen"]`.
    static func segments(_ path: String) -> [String] {
        var path = path
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            path = String(path[..<cut])
        }
        return path.split(separator: "/", omittingEmptySubsequences: true).map {
            String($0).removingPercentEncoding ?? String($0)
        }
    }

    /// The panel a path is on (its first segment), nil for the root `/`.
    static func panelId(_ path: String) -> String? {
        segments(path).first
    }

    /// The listed dashboard a path belongs to. The bare root `/` belongs to the first one (the frontend redirects
    /// it to the default panel, which the sidebar lists first).
    static func dashboard(for path: String?, in dashboards: [KhalaDashboard]) -> KhalaDashboard? {
        guard let path else { return nil }
        guard let panel = panelId(path) else { return dashboards.first }
        return dashboards.first { $0.id == panel }
    }

    /// The page that shows a view of a dashboard, the way `hui-root._navigateToView` builds it: the dashboard's
    /// route prefix, then the view's `path`, or its index when it has none.
    static func viewPath(prefix: String, view: KhalaDashboardView) -> String {
        let prefix = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        let segment = view.path ?? String(view.index)
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let encoded = segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
        return "\(prefix)/\(encoded)"
    }
}
