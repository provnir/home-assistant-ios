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
    /// `hasSidebar` also hides the frontend's header menu button (`ha-menu-button`), which would leave the web
    /// UI with no visible way back to the menu. This script keeps that button showing — in the header's own
    /// leading slot, where it never covers a title or a back arrow — so it becomes Khala's menu button on the
    /// web pages. It sets the button's `_alwaysVisible` (the frontend's own "show anyway" switch) before every
    /// update. If a future frontend renames it, the button just stays hidden and the edge swipe still opens
    /// the menu.
    @MainActor static var frontendUserScript: WKUserScript {
        WKUserScript(
            source: """
            (() => {
                const keepMenuButton = () => {
                    const button = customElements.get("ha-menu-button");
                    const proto = button && button.prototype;
                    if (!proto || proto.__khalaPatched || typeof proto.willUpdate !== "function") { return; }
                    const willUpdate = proto.willUpdate;
                    proto.willUpdate = function (changed) {
                        this._alwaysVisible = true;
                        return willUpdate.call(this, changed);
                    };
                    proto.__khalaPatched = true;
                };
                if (window.customElements) {
                    customElements.whenDefined("ha-menu-button").then(keepMenuButton);
                }
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }
}
