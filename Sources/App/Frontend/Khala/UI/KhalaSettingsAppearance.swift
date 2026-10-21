import Shared
import SwiftUI

/// Khala's look for the companion app's own settings screens (General, Notifications, Servers, ...) when the
/// Settings screen pushes them: they are hosted as they are, and only the environment is styled — Khala's
/// ground behind the list (its own background hidden), ink as the tint, the large title in the navigation bar,
/// mockup-height rows. Inset-grouped lists then read as white cards on Khala's ground. Screens a hosted screen
/// pushes further inherit the tint but not the ground (each pushed view brings its own background).
struct KhalaSettingsAppearance: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 52)
                .tint(KhalaTheme.ink)
                .background { KhalaGround() }
                .navigationBarTitleDisplayMode(.large)
        } else {
            content
        }
    }
}

extension View {
    /// Khala's appearance for a hosted companion-app settings screen, when the Khala shell is on.
    @MainActor
    func khalaSettingsAppearance() -> some View {
        modifier(KhalaSettingsAppearance(isEnabled: KhalaShell.isEnabled))
    }
}
