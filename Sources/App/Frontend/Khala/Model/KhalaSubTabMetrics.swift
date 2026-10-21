import Foundation

/// Geometry of the floating glass sub-tab bar (`KhalaSubTabBar`): a capsule sized to its tabs, centred, never
/// closer than `sideMargin` to the screen's edges (mockup `DaySettingsPage`: 24 pt), like the iOS 26 floating
/// tab bars — not an edge-to-edge footer. Pure, so the sizing is tested on Linux.
enum KhalaSubTabMetrics {
    /// The capsule's height; the lens is `lensHeight` inside it.
    static let barHeight: Double = 62
    static let lensHeight: Double = 52
    /// Between the capsule's ends and the first/last tab.
    static let inset: Double = 5
    /// The least room left on each side of the capsule.
    static let sideMargin: Double = 24
    /// A tab's width when there is room: enough for "Integrations" at the bar's 10 pt label.
    static let preferredTabWidth: Double = 80
    /// Below this a tab's label scales down (`minimumScaleFactor`) rather than the tab shrinking further.
    static let minimumTabWidth: Double = 52

    /// One tab's width for `count` tabs on a screen `available` points wide.
    static func tabWidth(available: Double, count: Int) -> Double {
        guard count > 0 else { return 0 }
        let room = (available - 2 * sideMargin - 2 * inset) / Double(count)
        return max(minimumTabWidth, min(preferredTabWidth, room))
    }

    /// The capsule's width for `count` tabs of `tabWidth`.
    static func barWidth(tabWidth: Double, count: Int) -> Double {
        tabWidth * Double(count) + 2 * inset
    }

    /// Where the lens sits for `selection` (clamped to the tabs there are), from the capsule's leading edge.
    static func lensOffset(selection: Int, count: Int, tabWidth: Double) -> Double {
        guard count > 0 else { return inset }
        return inset + Double(min(max(selection, 0), count - 1)) * tabWidth
    }
}
