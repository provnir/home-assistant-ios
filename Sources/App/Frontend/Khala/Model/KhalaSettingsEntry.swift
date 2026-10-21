import Foundation

/// One thing the Settings search can find: a Home Assistant settings section or page (opened in the web UI under
/// Khala's chrome) or one of the app's own settings screens.
struct KhalaSettingsEntry: Hashable, Identifiable {
    enum Target: Hashable {
        /// A frontend path (`/config/logs`).
        case serverPage(path: String)
        /// One of the app's settings screens, by the id the UI gave it (an upstream `SettingsItem` raw value).
        case app(id: String)
    }

    let id: String
    let title: String
    /// Where it lives ("Devices & services", "This app"); nil for a top-level row.
    let subtitle: String?
    let glyph: KhalaSettingsGlyph
    let keywords: [String]
    let target: Target
}
