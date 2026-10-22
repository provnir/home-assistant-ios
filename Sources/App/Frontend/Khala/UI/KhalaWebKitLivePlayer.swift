import HAKit
import os
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
/// the page or a timer comes back through `post(_:)`, and one that arrives on another thread is moved to main
/// rather than trapping.
///
/// Teardown is idempotent (`invalidate()`, also run by `deinit`): once invalidated nothing reaches the signaling,
/// the page, HAKit or the host again. Build 30.1 crashed right after giving way to HLS; the hand-off is now
/// sequenced — page stopped (peer connection closed, media released) and the WebKit callback stack left — before
/// the host is told, and every late callback (script message, evaluate completion, navigation delegate, timer,
/// HAKit) is dropped by the invalidated flag or by the attempt numbers.
final class KhalaWebKitLiveSession: NSObject, ObservableObject {
    @Published private(set) var showLoader = true
    @Published private(set) var didFail = false
    @Published private(set) var codec: String?
    @Published private(set) var isMuted = true

    let webView: WKWebView

    private static let log = os.Logger(subsystem: "il.co.provizor.khala", category: "live")

    private let server: Server
    private let cameraEntityId: String
    private let scriptHandler: KhalaWeakScriptHandler
    private var signaling = KhalaWebRTCSignaling()
    private var gate: WebRTCServerConnectionGate?
    private var offerSubscription: HACancellable?
    private var socketObserver: NSObjectProtocol?
    private var deadlines: [DispatchWorkItem] = []
    /// Events that arrived while the effects of another were being performed (an evaluate completion WebKit
    /// calls synchronously, say): handled after it, never inside it.
    private var pendingEvents: [KhalaWebRTCSignaling.Event] = []
    private var isHandling = false
    private var isInvalidated = false
    private var isHandingOff = false

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
        self.scriptHandler = handler

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
        let handler = scriptHandler
        let alreadyReleased = isInvalidated
        // WebKit wants its objects on the main thread; the last release of a session normally is, but a late
        // HAKit or timer callback can briefly hold it elsewhere.
        if Thread.isMainThread {
            handler.target = nil
            if !alreadyReleased { KhalaWebKitLiveSession.releasePage(of: webView) }
        } else {
            DispatchQueue.main.async {
                handler.target = nil
                if !alreadyReleased { KhalaWebKitLiveSession.releasePage(of: webView) }
            }
        }
    }

    func start() {
        guard !isInvalidated else { return }
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
        guard !isInvalidated else { return }
        isMuted.toggle()
        evaluate(.setMuted(isMuted))
    }

    /// Everything the session holds, released once: timers, the gate, the server subscription (closing the
    /// session on the server), the socket observer, the script handler, the navigation delegate and the page's
    /// peer connection and media. Safe to call any number of times.
    func invalidate() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.invalidate() }
            return
        }
        guard !isInvalidated else { return }
        isInvalidated = true
        pendingEvents.removeAll()
        deadlines.forEach { $0.cancel() }
        deadlines.removeAll()
        gate?.cancel()
        gate = nil
        offerSubscription?.cancel()
        offerSubscription = nil
        if let socketObserver {
            NotificationCenter.default.removeObserver(socketObserver)
            self.socketObserver = nil
        }
        scriptHandler.target = nil
        Self.releasePage(of: webView)
    }

    /// Stops the page's stream and detaches the web view from us. Never touches the session, so `deinit` can use it.
    private static func releasePage(of webView: WKWebView) {
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: KhalaWebRTCPage.messageHandler)
        webView.evaluateJavaScript("window.khala && window.khala.stop(); true", completionHandler: nil)
        webView.stopLoading()
    }

    // MARK: - Signaling

    private func send(_ event: KhalaWebRTCSignaling.Event) {
        guard Thread.isMainThread else {
            post(event)
            return
        }
        guard !isInvalidated else { return }
        pendingEvents.append(event)
        guard !isHandling else { return }
        isHandling = true
        defer { isHandling = false }
        while !pendingEvents.isEmpty, !isInvalidated {
            let next = pendingEvents.removeFirst()
            for effect in signaling.handle(next) {
                guard !isInvalidated else { break }
                perform(effect)
            }
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
            self.gate?.cancel()
            self.gate = gate
            gate.whenReady(requiringFreshConnection: freshConnection) { [weak self] isReady in
                self?.post(isReady ? .serverReady(attempt: attempt) : .serverUnusable(attempt: attempt))
            }

        case let .fetchClientConfig(attempt):
            gate?.cancel()
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
                        Self.log.info("client config failed, using default ICE servers")
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
            Self.log.info("\(self.cameraEntityId, privacy: .public): first frame")
            showLoader = false
        case let .codec(name):
            codec = name

        case let .fallBack(failure):
            handOff(failure)
        }
    }

    /// Gives way to the next player. The signaling has already queued the page's stop and the unsubscribe; the
    /// host is told only once that stop has run in the page (its completion, or half a second at most) and on a
    /// fresh turn of the main queue, so HLS's AVPlayer and audio session are never set up while WebKit is still
    /// tearing its peer connection down, and never from inside a WebKit callback.
    private func handOff(_ failure: KhalaLiveFailure) {
        guard !isHandingOff else { return }
        isHandingOff = true
        let reason = failure.logDescription
        Self.log.error("\(self.cameraEntityId, privacy: .public): WebKit WebRTC gave way: \(reason, privacy: .public)")
        Current.Log.info("Khala live: \(cameraEntityId) WebKit WebRTC gave way (\(reason))")
        KhalaLiveEngineStore.memory.record(failure, cameraEntityId: cameraEntityId)
        codec = nil

        var told = false
        let tell: () -> Void = { [weak self] in
            guard !told else { return }
            told = true
            DispatchQueue.main.async {
                guard let self else { return }
                self.invalidate()
                self.didFail = true
            }
        }
        webView.evaluateJavaScript("true") { _, _ in tell() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { tell() }
    }

    private func evaluate(_ command: KhalaWebRTCPageCommand) {
        guard !isInvalidated else { return }
        webView.evaluateJavaScript(command.javaScript) { [weak self] _, error in
            guard let error, let self, !self.isInvalidated else { return }
            // A call that returns nothing WebKit can bridge is not a failure.
            if let webKitError = error as? WKError, webKitError.code == .javaScriptResultTypeIsUnsupported { return }
            let code = (error as NSError).code
            guard command.isEssential else {
                Self.log.info("\(self.cameraEntityId, privacy: .public): page call failed (\(code)), ignored")
                return
            }
            // `window.khala` missing means the page is not there; anything else threw inside it. The signaling
            // ignores this once the stream is stopped or has already given way.
            send(.page(.error(message: "evaluate failed (\(code))")))
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
        guard socketObserver == nil, !isInvalidated else { return }
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
        guard !isInvalidated, let message = KhalaWebRTCPageMessage(body: body) else { return }
        let camera = cameraEntityId
        switch message {
        case let .note(text):
            let note = KhalaLiveFailure.redacted(text)
            Self.log.info("\(camera, privacy: .public): page: \(note, privacy: .public)")
        case let .ice(state):
            Self.log.info("\(camera, privacy: .public): ICE \(state, privacy: .public)")
        case let .error(text):
            let error = KhalaLiveFailure.redacted(text)
            Self.log.error("\(camera, privacy: .public): page error: \(error, privacy: .public)")
        default:
            break
        }
        send(.page(message))
    }

    private static func message(of error: Error) -> String {
        if let haError = error as? HAError, case let .external(external) = haError {
            return external.message
        }
        return error.localizedDescription
    }
}

/// The app session's live-engine state: the hidden setting (`KhalaLiveEngine`, App settings → General → Khala)
/// and the per-camera fallback memory. Main thread only.
enum KhalaLiveEngineStore {
    static var memory = KhalaLiveFallbackMemory()

    static var engine: KhalaLiveEngine {
        get { KhalaLiveEngine(stored: UserDefaults.standard.string(forKey: KhalaLiveEngine.defaultsKey)) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: KhalaLiveEngine.defaultsKey) }
    }

    /// The camera's player plan with the engine setting and the memory applied (both hosts use it).
    static func plan(_ players: [CameraPlayerType], cameraEntityId: String) -> [CameraPlayerType] {
        let skips = memory.skipsWebKit(cameraEntityId: cameraEntityId)
        let planned = engine.plan(players, webRTC: .webRTC, webKitFailedRepeatedly: skips)
        if planned != players {
            Current.Log.info("Khala live: \(cameraEntityId) skips WebKit WebRTC (engine \(engine.rawValue))")
        }
        return planned
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

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        send(.page(.error(message: "page failed to load")))
    }
}

/// `WKUserContentController` holds its handlers strongly; this keeps it from holding the session.
final class KhalaWeakScriptHandler: NSObject, WKScriptMessageHandler {
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

    /// The container goes; the web view is the session's and leaves with it (only if it is still ours).
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        for subview in uiView.subviews {
            subview.removeFromSuperview()
        }
    }
}
