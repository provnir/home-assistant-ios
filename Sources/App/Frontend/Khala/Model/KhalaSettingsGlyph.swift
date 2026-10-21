import Foundation

/// The glyph of a Settings row or a server page's tab; `KhalaSettingsSymbols` (UI) draws each as an SF Symbol.
enum KhalaSettingsGlyph: String, Hashable {
    // Home Assistant
    case cloud, devices, automations, areas, apps, dashboards, connectivity, voice, people, system, tools, about
    // Sub-pages (tabs and the pages behind System and Connectivity)
    case integrations, entities, helpers, scenes, scripts, blueprints, labels, zones, users, tags
    case general, updates, repairs, logs, backups, network, storage, hardware, analytics, labs, radio
    // This app
    case servers, appGeneral, gestures, notifications, liveActivities, kiosk, privacy, appAbout, more
    /// Anything without a glyph of its own.
    case page
}
