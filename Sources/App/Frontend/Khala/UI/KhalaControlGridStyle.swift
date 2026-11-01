import Foundation

/// How `KhalaControlGrid` lays its controls out.
enum KhalaControlGridStyle: Equatable {
    /// 76 pt tiles in a wrapping grid (device screens, the car's tabs).
    case tiles(columns: Int)
    /// Full-width white cards: a toggle as glyph chip + title + switch (the generic screen's Power row).
    case card
    /// The media sheet's flat rows: power switch, volume slider, source buttons, sound-mode dropdown.
    case sheet
}
