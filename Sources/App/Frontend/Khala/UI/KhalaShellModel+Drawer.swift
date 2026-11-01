import SwiftUI
import UIKit

/// The shell's side of the menu drawer (`KhalaDrawer`): what the drawer needs to know about the screen on the card,
/// and what follows its motion.
extension KhalaShellModel {
    /// The web UI is on the card and up (Dashboards, connected or loaded). Before that the stand-by screen covers it
    /// and counts as a native screen for the drawer.
    var isWebScreen: Bool {
        destination == .dashboards && isFrontendReady
    }

    /// The web UI's header shows Back in the leading slot (a sub-page or a dialog), so the shell's menu button stays
    /// off and the leading-edge swipe goes Back (one leading control, never both).
    var showsBackInHeader: Bool {
        guard isWebScreen else { return false }
        if let page = pageHeader { return page.back != .none }
        return dashboardHeader.showsBack
    }

    /// The menu button (and the screens' own menu or search buttons, `menuRequests`): opens or closes with one light
    /// impact when the state changes.
    func setMenuOpen(_ open: Bool) {
        guard open != isMenuOpen else { return }
        drawer.playToggleFeedback()
        isMenuOpen = open
    }

    /// The header's Back, for the drawer's edge swipe too.
    func goBackFromHeader() {
        if pageHeader != nil {
            withAnimation(.spring(response: KhalaDrawerMath.settleDuration, dampingFraction: 1)) {
                goBackFromPage()
            }
        } else {
            goBackInFrontend()
        }
    }

    func connectDrawer() {
        drawer.context = { [weak self] in
            guard let self else { return KhalaDrawer.Context() }
            return KhalaDrawer.Context(isWebScreen: isWebScreen, showsBack: showsBackInHeader)
        }
        drawer.onCommit = { [weak self] open in
            self?.isMenuOpen = open
        }
        drawer.onBack = { [weak self] in
            self?.goBackFromHeader()
        }
        drawer.onProgress = { [weak self] progress in
            self?.applyFrontendCorners(progress: progress)
        }
        drawer.extraPresenters = { [weak self] in
            guard let controller = self?.webViewController else { return [] }
            return [controller]
        }
    }

    /// The web UI's card gets the drawer's rounded corners as it moves, every frame, on the web view controller's
    /// own layer (a plain corner clip) rather than with a SwiftUI mask, which would render the web view offscreen
    /// for as long as it is on screen.
    func applyFrontendCorners(progress: Double) {
        guard let view = webViewController?.view else { return }
        let radius = destination == .dashboards ? CGFloat(KhalaDrawerMath.cornerRadius(progress: progress)) : 0
        guard view.layer.cornerRadius != radius else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = radius
        view.layer.masksToBounds = radius > 0
        CATransaction.commit()
    }

    /// While the shell is on, the leading screen edge belongs to the drawer (menu, or Back on a web sub-page): the
    /// upstream web view's own leading-edge recognizer, which only acts at the end of the swipe and reaches the menu
    /// through a JavaScript round trip (`sidebar/show`), is switched off so the menu never opens twice. Its trailing
    /// edge and the 2/3-finger swipes keep the user's gesture settings. Off on Catalyst and in kiosk mode, where the
    /// app is the stock frontend.
    func takeLeadingEdge(from controller: WebViewController) {
        guard KhalaShell.isEnabled else { return }
        let rightToLeft = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft
        let leading = rightToLeft ? controller.rightEdgeGestureRecognizer : controller.leftEdgePanGestureRecognizer
        leading.isEnabled = false
    }
}
