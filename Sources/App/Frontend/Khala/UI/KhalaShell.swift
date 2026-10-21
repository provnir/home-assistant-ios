import Combine
import Shared
import WebKit

/// What the Khala shell asks of the rest of the app, decided in one place so the frontend config, the web
/// view's user scripts and `KhalaShellView` can never disagree.
enum KhalaShell {
    /// The native shell (Today + menu) is on. Off on Mac Catalyst and in kiosk mode, where the app is just the
    /// web frontend. Read once per web view / page load: flipping it means a fresh frontend.
    @MainActor static var isEnabled: Bool {
        !Current.isCatalyst && !Current.kiosk.settings.enabled
    }

    /// Khala's menu is the app's only navigation. The app answers the frontend's `config/get` with
    /// `hasSidebar: true` while the shell is on (the App Labs tab bar's own mechanism), so the frontend never
    /// opens its sidebar and routes its menu requests — and the app's edge swipe, which reaches it as
    /// `sidebar/show` — back to the app as `sidebar/show` (`NativeTabBarState.requestMore()`), which opens
    /// Khala's menu. See home-assistant/frontend `src/layouts/home-assistant-main.ts` (`_externalSidebar`).
    ///
    /// With `hasSidebar` the frontend also hides its header menu button (`ha-menu-button`). That is fine: on the
    /// web UI Khala draws its own header (`KhalaDashboardHeaderView`, pinned menu button included) and the
    /// frontend's dashboard toolbar is hidden by `KhalaFrontendScript`, which this user script installs. See
    /// that type for what it relies on in the frontend and how it fails soft.
    /// Requests for the app's settings from outside the shell (the frontend's "Companion app" entry, external
    /// bus `config_screen/show`), which Khala answers with its own Settings screen.
    @MainActor static let settingsRequests = PassthroughSubject<Void, Never>()
    /// Shells listening for `settingsRequests` (one per connected server's shell on screen).
    @MainActor static var settingsListeners = 0

    /// Asks the shell on screen for its Settings screen; false when no shell listens (the caller then shows
    /// the app's settings its own way).
    @MainActor static func requestSettings() -> Bool {
        guard settingsListeners > 0 else { return false }
        settingsRequests.send()
        return true
    }

    @MainActor static var frontendUserScript: WKUserScript {
        WKUserScript(
            source: KhalaFrontendScript.source(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }
}
