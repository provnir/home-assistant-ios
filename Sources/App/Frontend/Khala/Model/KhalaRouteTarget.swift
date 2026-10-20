import Foundation

/// Where a tap in Khala lands. Never the web frontend: that only shows under Dashboards.
enum KhalaRouteTarget: Equatable {
    /// A full screen in the card.
    case screen(KhalaDestination)
    /// The media sheet over the current screen (theater, speakers, a car's player): the device it belongs to (for
    /// its name) and the `media_player` it controls.
    case mediaSheet(deviceId: String, entityId: String)
}
