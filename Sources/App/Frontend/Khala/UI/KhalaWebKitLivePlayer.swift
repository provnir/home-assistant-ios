import HAKit
import Shared
import SwiftUI
import WebKit

/// Live camera over Apple's own WebRTC: a small transparent WKWebView playing `KhalaWebRTCPage`, signaled natively
/// over the app's HAKit websocket.
///
/// The app's native player (`WebRTCVideoPlayerView`) runs Google's libwebrtc, which offers H.264/VP8 only, so an
/// H.265 camera behind go2rtc cannot negotiate and falls back to laggy HLS. WebKit's WebRTC offers H.265 and go2rtc
/// answers with it (checked against a real go2rtc: an offer carrying H265 is answered H265 first), which is why the
/// same camera plays instantly in the Dashboards tab. This player takes that path while keeping everything native
/// around it: the frontend's sequence (`camera/webrtc/get_client_config`, the `camera/webrtc/offer` subscription,
/// trickled `camera/webrtc/candidate`s) is `KhalaWebRTCSignaling`; this view only performs its effects.
///
/// It is a drop-in for `WebRTCVideoPlayerView` (same bindings, same "give up" callback), so the hosts' cascade —
/// WebRTC → HLS (with the still shown first) → MJPEG — is unchanged: no answer, failed ICE, a JavaScript error or no
/// frame within `KhalaWebRTCSignaling.Timing.firstFrame` calls `onWebRTCUnsupported`.
struct KhalaWebKitLivePlayer: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @StateObject private var session: KhalaWebKitLiveSession

    private let controlsVisible: Binding<Bool>
    private let showLoader: Binding<Bool>
    private let swipeDownDismisses: Bool
    private let onWebRTCUnsupported: (() -> Void)?
    private let onCodec: ((String?) -> Void)?

    /// - Parameters:
    ///   - fit: `.cover` in the 16:9 card (as its poster still), `.contain` full screen.
    ///   - swipeDownDismisses: full screen only, as the native player did; a card sits in a scroll view.
    ///   - onCodec: the decoded codec's name ("H.265") once known, for the LIVE badge.
    init(
        server: Server,
        cameraEntityId: String,
        cameraName: String? = nil,
        fit: KhalaWebRTCPage.Fit = .contain,
        swipeDownDismisses: Bool = false,
        controlsVisible: Binding<Bool>,
        showLoader: Binding<Bool>,
        onWebRTCUnsupported: (() -> Void)? = nil,
        onCodec: ((String?) -> Void)? = nil
    ) {
        self.controlsVisible = controlsVisible
        self.showLoader = showLoader
        self.swipeDownDismisses = swipeDownDismisses
        self.onWebRTCUnsupported = onWebRTCUnsupported
        self.onCodec = onCodec
        _session = StateObject(wrappedValue: KhalaWebKitLiveSession(
            server: server,
            cameraEntityId: cameraEntityId,
            fit: fit
        ))
    }

    var body: some View {
        // Same chrome as the native player (mute in the bar); no talkback, which needs the microphone.
        WebRTCVideoPlayerControlsView(
            controlsVisible: controlsVisible,
            isTalkbackSupported: false,
            isTalking: false,
            isMuted: session.isMuted,
            onToggleTalkback: {},
            onToggleMute: { session.toggleMute() }
        ) {
            KhalaWebKitLiveView(webView: session.webView)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsVisible.wrappedValue.toggle()
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 30).onEnded { value in
                        if swipeDownDismisses, value.translation.height > 100 { dismiss() }
                    },
                    including: swipeDownDismisses ? .all : .subviews
                )
        }
        .onAppear { session.start() }
        .onDisappear { session.stop() }
        .onChange(of: session.didFail) { didFail in
            if didFail { onWebRTCUnsupported?() }
        }
        .onChange(of: session.showLoader) { isLoading in
            showLoader.wrappedValue = isLoading
        }
        .onChange(of: session.codec) { codec in
            onCodec?(codec)
        }
        // Gone to the background: the peer connection and the server's session are closed, not left running
        // unseen; back in front, a fresh one starts. `.inactive` (a passing overlay) keeps the stream.
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background: session.background()
            case .active: session.foreground()
            default: break
            }
        }
    }
}

/// Holds the web view and runs `KhalaWebRTCSignaling`'s effects. Main-thread confined: every callback from HAKit,
/// the page or a timer comes back through `post(_:)`.
final class KhalaWebKitLiveSession: NSObject, ObservableObject {
    @Published private(set) var showLoader = true
    @Published private(set) var didFail = false
    @Published private(set) var codec: String?
    @Published private(set) var isMuted = true

    let webView: WKWebView

    private let server: Server
    private let cameraEntityId: String
    private var signaling = KhalaWebRTCSignaling()
    private var gate: WebRTCServerConnectionGate?
    private var offerSubscription: HACancellable?
    private var socketObserver: NSObjectProtocol?
    private var deadlines: [DispatchWorkItem] = []

    init(server: Server, cameraEntityId: String, fit: KhalaWebRTCPage.Fit) {
        self.server = server
        self.cameraEntityId = cameraEntityId

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.websiteDataStore = .nonPersistent()
        let handler = KhalaWeakScriptHandler()
        configuration.userContentController.add(handler, name: KhalaWebRTCPage.messageHandler)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Taps belong to the SwiftUI layer around it (controls, full screen); the page takes none.
        webView.isUserInteractionEnabled = false
        webView.allowsLinkPreview = false
        self.webView = webView
        super.init()

        handler.target = self
        webView.navigationDelegate = self
        webView.loadHTMLString(KhalaWebRTCPage.html(fit: fit), baseURL: nil)
    }

    deinit {
        deadlines.forEach { $0.cancel() }
        gate?.cancel()
        offerSubscription?.cancel()
        if let socketObserver {
            NotificationCenter.default.removeObserver(socketObserver)
        }
        let webView = webView
        DispatchQueue.main.async {
            webView.configuration.userContentController.removeScriptMessageHandler(
                forName: KhalaWebRTCPage.messageHandler
            )
            webView.stopLoading()
        }
    }

    func start() {
        didFail = false
        showLoader = true
        send(.start)
    }

    func stop() {
        send(.stop)
    }

    func background() {
        send(.backgrounded)
    }

    func foreground() {
        send(.foregrounded)
    }

    func toggleMute() {
        isMuted.toggle()
        evaluate(.setMuted(isMuted))
    }

    // MARK: - Signaling

    private func send(_ event: KhalaWebRTCSignaling.Event) {
        dispatchPrecondition(condition: .onQueue(.main))
        for effect in signaling.handle(event) {
            perform(effect)
        }
    }

    /// Callbacks re-enter on the next turn of the main queue, never inside the effects of the event that asked.
    private func post(_ event: KhalaWebRTCSignaling.Event) {
        DispatchQueue.main.async { [weak self] in
            self?.send(event)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func perform(_ effect: KhalaWebRTCSignaling.Effect) {
        switch effect {
        case let .waitForServer(attempt, freshConnection):
            guard let api = Current.api(for: server) else {
                post(.serverUnusable(attempt: attempt))
                return
            }
            observeSocket(api.connection)
            let gate = WebRTCServerConnectionGate(connection: api.connection)
            self.gate = gate
            gate.whenReady(requiringFreshConnection: freshConnection) { [weak self] isReady in
                self?.post(isReady ? .serverReady(attempt: attempt) : .serverUnusable(attempt: attempt))
            }

        case let .fetchClientConfig(attempt):
            gate = nil
            guard let api = Current.api(for: server) else {
                post(.serverUnusable(attempt: attempt))
                return
            }
            // Frontend `fetchWebRtcClientConfiguration`: ICE servers (with any TURN) and the data channel label.
            api.connection.send(.init(
                type: .webSocket("camera/webrtc/get_client_config"),
                data: ["entity_id": cameraEntityId]
            )) { [weak self] result in
                switch result {
                case let .success(data):
                    var json: [String: Any] = [:]
                    if case let .dictionary(answer) = data { json = answer }
                    let config = KhalaWebRTCClientConfig(json: json, fallbackICEServers: AppConstants.WebRTC.iceServers)
                    self?.post(.clientConfig(attempt: attempt, config))
                case let .failure(error):
                    if KhalaLiveFailure.isUnsupported(message: Self.message(of: error)) {
                        self?.post(.clientConfigUnsupported(attempt: attempt))
                    } else {
                        self?.post(.clientConfig(attempt: attempt, nil))
                    }
                }
            }

        case let .subscribeOffer(attempt, sdp):
            guard let api = Current.api(for: server) else {
                post(.serverUnusable(attempt: attempt))
                return
            }
            offerSubscription?.cancel()
            // Frontend `webRtcOffer`: a subscription whose events are session, answer, candidate and error.
            offerSubscription = api.connection.subscribe(
                to: .init(
                    type: .webSocket("camera/webrtc/offer"),
                    data: ["entity_id": cameraEntityId, "offer": sdp]
                ),
                initiated: { [weak self] result in
                    if case let .failure(error) = result {
                        self?.post(.offerRejected(attempt: attempt, message: Self.message(of: error)))
                    }
                },
                handler: { [weak self] _, data in
                    guard case let .dictionary(json) = data, let event = KhalaWebRTCServerEvent(json: json) else {
                        return
                    }
                    self?.post(.server(attempt: attempt, event))
                }
            )

        case let .sendCandidate(sessionId, candidate):
            guard let api = Current.api(for: server) else { return }
            api.connection.send(.init(
                type: .webSocket("camera/webrtc/candidate"),
                data: ["entity_id": cameraEntityId, "session_id": sessionId, "candidate": candidate.json]
            )) { [cameraEntityId] result in
                if case let .failure(error) = result {
                    // One refused candidate is not fatal; ICE goes on with the others.
                    Current.Log.info("Khala live: \(cameraEntityId) candidate refused: \(error.localizedDescription)")
                }
            }

        case .unsubscribe:
            gate?.cancel()
            gate = nil
            // HAKit sends `unsubscribe_events`; core then closes the WebRTC session.
            offerSubscription?.cancel()
            offerSubscription = nil

        case let .page(command):
            evaluate(command)

        case let .armFirstFrameDeadline(attempt, after):
            schedule(after: after, .firstFrameDeadline(attempt: attempt))
        case let .armServerWaitDeadline(attempt, after):
            schedule(after: after, .serverWaitDeadline(attempt: attempt))
        case let .armRecoveryDeadline(attempt, after):
            schedule(after: after, .recoveryDeadline(attempt: attempt))
        case .cancelDeadlines:
            deadlines.forEach { $0.cancel() }
            deadlines.removeAll()

        case .playing:
            showLoader = false
        case let .codec(name):
            codec = name

        case let .fallBack(failure):
            // The kind only: a server message can quote stream URLs, and nothing here may log a credential.
            Current.Log.info("Khala live: \(cameraEntityId) WebKit WebRTC gave way (\(Self.kind(of: failure)))")
            codec = nil
            didFail = true
        }
    }

    private func evaluate(_ command: KhalaWebRTCPageCommand) {
        webView.evaluateJavaScript(command.javaScript) { [weak self] _, error in
            guard let error, let self else { return }
            // A call that returns nothing WebKit can bridge is not a failure.
            if let webKitError = error as? WKError, webKitError.code == .javaScriptResultTypeIsUnsupported { return }
            // `window.khala` missing means the page is not there; anything else threw inside it. The signaling
            // ignores this once the stream is stopped or has already given way.
            send(.page(.error(message: "evaluate failed")))
        }
    }

    private func schedule(after delay: TimeInterval, _ event: KhalaWebRTCSignaling.Event) {
        let item = DispatchWorkItem { [weak self] in
            self?.send(event)
        }
        deadlines.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Core closes a session with the socket that opened it, and HAKit would resubscribe the old offer once the
    /// socket returns, so a lost socket rebuilds the attempt on the fresh one (`KhalaWebRTCSignaling.socketLost`).
    private func observeSocket(_ connection: HAConnection) {
        guard socketObserver == nil else { return }
        socketObserver = NotificationCenter.default.addObserver(
            forName: HAConnectionState.didTransitionToStateNotification,
            object: connection,
            queue: .main
        ) { [weak self, weak connection] _ in
            guard let self, let connection else { return }
            if case .ready = connection.state { return }
            post(.socketLost)
        }
    }

    fileprivate func receive(_ body: Any) {
        guard let message = KhalaWebRTCPageMessage(body: body) else { return }
        send(.page(message))
    }

    private static func message(of error: Error) -> String {
        if let haError = error as? HAError, case let .external(external) = haError {
            return external.message
        }
        return error.localizedDescription
    }

    private static func kind(of failure: KhalaLiveFailure) -> String {
        switch failure {
        case .unsupported: return "no WebRTC for this camera"
        case .noServer: return "server unreachable"
        case .signaling: return "signaling error"
        case .timeout: return "no frame in time"
        case .ice: return "ICE failed"
        case .page: return "page error"
        }
    }
}

extension KhalaWebKitLiveSession: WKNavigationDelegate {
    /// Only the page itself loads; it links nowhere.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let scheme = navigationAction.request.url?.scheme
        decisionHandler(scheme == nil || scheme == "about" ? .allow : .cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        send(.page(.error(message: "web content process ended")))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        send(.page(.error(message: "page failed to load")))
    }
}

/// `WKUserContentController` holds its handlers strongly; this keeps it from holding the session.
private final class KhalaWeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: KhalaWebKitLiveSession?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.receive(message.body)
    }
}

/// The session's web view, filling whatever the host gives it.
private struct KhalaWebKitLiveView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.clipsToBounds = true
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
