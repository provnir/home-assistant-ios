import Foundation

/// What a slider control sets.
enum KhalaSlider: Hashable {
    /// `light.turn_on` `brightness_pct`.
    case brightness
    /// `cover.set_cover_position`.
    case position
    /// `media_player.volume_set`.
    case volume
    /// `fan.set_percentage`, snapping to the fan's `percentage_step`.
    case percentage(step: Double)
}
