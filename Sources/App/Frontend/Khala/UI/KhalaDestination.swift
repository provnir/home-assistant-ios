import Foundation

/// The places the Khala menu switches the screen card between. Settings is an action (it opens the app's existing
/// Settings sheet), not a destination.
enum KhalaDestination: String, CaseIterable, Identifiable {
    case today
    case cameras
    case automations
    /// The app's stock web frontend (Lovelace dashboards and everything else HA's web UI does).
    case dashboards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return KhalaText.today
        case .cameras: return KhalaText.cameras
        case .automations: return KhalaText.automations
        case .dashboards: return KhalaText.dashboards
        }
    }
}
