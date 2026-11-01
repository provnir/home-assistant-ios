import SwiftUI
import UIKit

extension View {
    /// Marks a SwiftUI control that drags sideways itself (a level or volume slider, a tab bar), so a drag that
    /// starts on it is left to it and never opens the menu drawer (`KhalaDrawer`). SwiftUI controls have no UIView of
    /// their own in the hit-test chain; this puts a touch-transparent marker view behind the control, whose frame
    /// the drawer checks at touch-down.
    func khalaClaimsHorizontalDrags() -> some View {
        background(KhalaDrawerExclusion())
    }
}

/// The marker behind a control marked with `khalaClaimsHorizontalDrags()`.
struct KhalaDrawerExclusion: UIViewRepresentable {
    /// Every marker on screen (weakly held).
    @MainActor private static let markers = NSHashTable<Marker>.weakObjects()

    /// Whether a touch at `windowPoint` lands on a marked control in `window`.
    @MainActor static func contains(windowPoint: CGPoint, in window: UIWindow?) -> Bool {
        guard let window else { return false }
        return markers.allObjects.contains { marker in
            marker.window === window && !marker.isHiddenInHierarchy
                && marker.bounds.contains(marker.convert(windowPoint, from: nil))
        }
    }

    func makeUIView(context: Context) -> Marker {
        let marker = Marker()
        marker.backgroundColor = .clear
        marker.isUserInteractionEnabled = false
        marker.isAccessibilityElement = false
        Self.markers.add(marker)
        return marker
    }

    func updateUIView(_ marker: Marker, context: Context) {}

    final class Marker: UIView {
        /// Hidden itself or under a hidden or transparent ancestor (a screen faded out but still mounted).
        var isHiddenInHierarchy: Bool {
            var view: UIView? = self
            while let current = view {
                if current.isHidden || current.alpha < 0.01 { return true }
                view = current.superview
            }
            return false
        }
    }
}

#Preview {
    Rectangle()
        .frame(height: 48)
        .khalaClaimsHorizontalDrags()
        .padding()
}
