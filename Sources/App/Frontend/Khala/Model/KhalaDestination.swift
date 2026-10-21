import Foundation

/// What the Khala screen card shows. The first four are the menu's destinations; the others are the native
/// screens a tap opens (a camera, a device, any other entity), each with a back button to where it came from.
/// Settings is a destination of its own at the bottom of the menu (the app's and the server's settings in one
/// screen); the server's pages it opens show in the web UI (`dashboards`) under Khala's page chrome.
enum KhalaDestination: Hashable, Identifiable, CaseIterable {
    case today
    case cameras
    case automations
    /// The app's stock web frontend (Lovelace dashboards and everything else HA's web UI does).
    case dashboards
    /// App and server settings in one screen (`KhalaSettingsView`).
    case settings
    /// One camera's screen (live view, today's detections, events, settings).
    case camera(entityId: String)
    /// A listed device's screen (car, hot water, any other), by `KhalaDevice.id`.
    case device(id: String)
    /// The native screen of an entity that belongs to no listed device.
    case entity(entityId: String)

    /// The menu's destinations, in order.
    static var allCases: [KhalaDestination] { [.today, .cameras, .automations, .dashboards] }

    var id: String {
        switch self {
        case .today: return "today"
        case .cameras: return "cameras"
        case .automations: return "automations"
        case .dashboards: return "dashboards"
        case .settings: return "settings"
        case let .camera(entityId): return "camera:\(entityId)"
        case let .device(id): return "device:\(id)"
        case let .entity(entityId): return "entity:\(entityId)"
        }
    }

    var title: String {
        switch self {
        case .today: return KhalaText.today
        case .cameras, .camera: return KhalaText.cameras
        case .automations: return KhalaText.automations
        case .dashboards: return KhalaText.dashboards
        case .settings: return KhalaText.settings
        case .device, .entity: return KhalaText.devicesTitle
        }
    }

    /// One of the menu's own destinations (as opposed to a screen opened from one).
    var isMenuDestination: Bool {
        Self.allCases.contains(self)
    }

    /// The menu row to highlight while this is on screen: a camera's screen belongs to Cameras.
    var menuHighlight: KhalaDestination? {
        switch self {
        case .today, .cameras, .automations, .dashboards, .settings: return self
        case .camera: return .cameras
        case .device, .entity: return nil
        }
    }
}
