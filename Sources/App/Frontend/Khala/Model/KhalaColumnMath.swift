import Foundation

/// How wide a native screen's content runs, and how many tiles a grid puts in a row, on any width the app gets:
/// an iPhone, the iPhone Duo's outer (compact) and inner (regular) displays, Split View halves, an iPad.
///
/// Apple's iPhone Duo guidance (Tech Talks "Prepare your app for iPhone Duo" and "Design for iPhone Duo"): lay out by
/// size class and available width, never by device, idiom or orientation, because the same scene resizes in place
/// when the device opens or closes. In a compact width the content keeps the full width it always had; in a
/// regular width it is held to a readable column, centred, while the ground still reaches the display's edges.
enum KhalaColumnMath {
    /// The readable column: text-led screens (Today's timeline, Settings, a device's sections).
    static let readableWidth = 680.0
    /// The wide column: tile grids (Cameras), which use the room for more tiles instead of bigger ones.
    static let wideWidth = 1040.0

    enum Kind: Equatable {
        case readable
        case wide

        var maximumWidth: Double {
            switch self {
            case .readable: return KhalaColumnMath.readableWidth
            case .wide: return KhalaColumnMath.wideWidth
            }
        }
    }

    /// The content's maximum width, or nil for "the whole width" (compact width: unchanged from before).
    static func maximumWidth(kind: Kind, isRegularWidth: Bool) -> Double? {
        isRegularWidth ? kind.maximumWidth : nil
    }

    /// Camera tiles: two per row on a phone-sized width (as before), more as the width allows, never fewer than
    /// two and each at least `minimumTileWidth` wide.
    static let minimumTileWidth = 200.0

    static func tileColumns(available: Double, spacing: Double, minimum: Int = 2) -> Int {
        guard available > 0 else { return minimum }
        let fits = Int(((available + spacing) / (minimumTileWidth + spacing)).rounded(.down))
        return max(minimum, fits)
    }
}
