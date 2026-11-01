import Foundation

/// A control's or device's glyph: an SF Symbol, or a Material Design icon name from Home Assistant (registry icon
/// or HA's own icon resolution) drawn when no SF Symbol maps (decision 4: SF Symbols first).
enum KhalaGlyph: Hashable {
    case sf(String)
    case mdi(String)
}
