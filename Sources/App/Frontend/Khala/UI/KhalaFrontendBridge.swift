import Combine
import Shared
import WebKit

/// Receives what `KhalaFrontendScript` posts from the web frontend (`khalaShell` script messages, main frame of an
/// allowed server origin only — registered behind `SafeScriptMessageHandler`) and publishes it for the shell.
/// Owned by the `WebViewController`, so it lives exactly as long as the web view it listens to.
final class KhalaFrontendBridge: NSObject, WKScriptMessageHandler {
    /// The script's latest report; nil until the first one (or when the script isn't running at all).
    let state = CurrentValueSubject<KhalaFrontendState?, Never>(nil)

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch body["type"] as? String {
        case "state":
            guard let state = KhalaFrontendState(json: body["state"]) else {
                Current.Log.warning("Khala: unreadable frontend state")
                return
            }
            if state != self.state.value {
                self.state.send(state)
            }
        case "problem":
            // A frontend this script doesn't fully know: the shell keeps working, with the frontend's own
            // header showing under the native one where hiding it failed.
            Current.Log.warning("Khala frontend script: \(body["message"] as? String ?? "unknown problem")")
        default:
            break
        }
    }
}
