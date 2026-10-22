import Alamofire
import AVFoundation
import HAKit
import os
import Shared
import SwiftUI
import WebKit

/// Live camera as the Home Assistant frontend plays it: `KhalaWebRTCPage` (the frontend's `ha-camera-stream`,
/// `ha-web-rtc-player` and `ha-hls-player`, ported) in a WKWebView, with native signaling over the app's HAKit
/// websocket and a native shell around it — zoom, full screen, picture in picture, a full-resolution snapshot,
/// mute with memory and an info sheet.
///
/// Apple's WebRTC in WebKit offers the H.265 the cameras send through go2rtc, which the app's bundled libwebrtc
/// (H.264/VP8 only) cannot, so this is the path that plays them instantly. As in the frontend, WebRTC and HLS race
/// in the same page and the selection (`KhalaStreamSelection`) shows the winner; the HLS lane is WebKit's own HLS, so
/// a WebRTC failure switches lanes in place without leaving the page, its layout or its zoom.
///
/// It is still a drop-in for `WebRTCVideoPlayerView` in the hosts' cascade: when neither lane can play
/// (`KhalaLiveStage.Effect.giveUp`), `onWebRTCUnsupported` moves the host on to AVPlayer HLS, then MJPEG.
struct KhalaWebKitLivePlayer: View {
    enum Style {
        /// In a card: compact controls, no swipe-down.
        case card
        /// The full-screen overlay: the whole control bar and swipe down to close.
        case fullScreen
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @StateObject private var session: KhalaWebKitLiveSession

    private let style: Style
    private let cameraName: String?
    private let poster: UIImage?
    private let controller: KhalaLiveController?
    private let controlsVisible: Binding<Bool>
    private let showLoader: Binding<Bool>
    private let onWebRTCUnsupported: (() -> Void)?
    private let onPath: ((KhalaLivePath?) -> Void)?

    @State private var zoomScale: CGFloat = 1
    @State private var zoomResetToken = 0
    @State private var dismissProgress: CGFloat = 0
    @State private var snapshot: KhalaSnapshot?
    @State private var isTakingSnapshot = false
    @State private var showsInfo = false

    /// - Parameters:
    ///   - lanes: what the page runs (`KhalaLiveEngineStore.lanes`): WebRTC and, when the camera offers it, HLS.
    ///   - fit: `.cover` in the 16:9 card (as its poster still), `.contain` full screen.
    ///   - poster: the camera's latest still, shown in the page's video elements until the first frame.
    ///   - controller: lets the host ask for the live frame (the card's Snapshot button).
    ///   - onPath: the lane on screen and its codec ("WebRTC · H.265"), once it plays, for the LIVE badge.
    init(
        server: Server,
        cameraEntityId: String,
        cameraName: String? = nil,
        lanes: KhalaLiveLanes = KhalaLiveLanes(webRTC: true, hls: false),
        fit: KhalaWebRTCPage.Fit = .contain,
        style: Style = .fullScreen,
        poster: UIImage? = nil,
        controller: KhalaLiveController? = nil,
        controlsVisible: Binding<Bool>,
        showLoader: Binding<Bool>,
        onWebRTCUnsupported: (() -> Void)? = nil,
        onPath: ((KhalaLivePath?) -> Void)? = nil
    ) {
        self.style = style
        self.cameraName = cameraName
        self.poster = poster
        self.controller = controller
        self.controlsVisible = controlsVisible
        self.showLoader = showLoader
        self.onWebRTCUnsupported = onWebRTCUnsupported
        self.onPath = onPath
        _session = StateObject(wrappedValue: KhalaWebKitLiveSession(
            server: server,
            cameraEntityId: cameraEntityId,
            lanes: lanes,
            fit: fit
        ))
    }

    var body: some View {
        ZStack {
            KhalaLiveZoomView(
                webView: session.webView,
                allowsSwipeDown: style == .fullScreen,
                resetToken: zoomResetToken,
                onTap: {
                    withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.wrappedValue.toggle() }
                },
                onLongPress: { showsInfo = true },
                onZoom: { zoomScale = $0 },
                onDismissProgress: { dismissProgress = $0 },
                onDismiss: { dismiss() }
            )
            .ignoresSafeArea(style == .fullScreen ? .all : [])

            KhalaLiveControls(
                style: style,
                isVisible: controlsVisible.wrappedValue && dismissProgress == 0,
                isMuted: session.isMuted,
                isPictureInPicture: session.isPictureInPicture,
                isPlaying: !session.isLoading,
                isTakingSnapshot: isTakingSnapshot,
                zoomLabel: KhalaLiveZoom.label(zoomScale),
                onMute: { session.toggleMute() },
                onPictureInPicture: { session.togglePictureInPicture() },
                onSnapshot: { takeSnapshot() },
                onInfo: { showsInfo = true },
                onResetZoom: { zoomResetToken += 1 }
            )
        }
        .onAppear {
            controller?.session = session
            session.setPoster(poster)
            session.start()
        }
        .onDisappear { session.stop() }
        .onChange(of: poster) { session.setPoster($0) }
        .onChange(of: session.didFail) { didFail in
            if didFail { onWebRTCUnsupported?() }
        }
        .onChange(of: session.isLoading) { isLoading in
            showLoader.wrappedValue = isLoading
        }
        .onChange(of: session.path) { path in
            onPath?(path)
        }
        // Gone to the background: as the frontend, the stream is kept for 60 s (and for good while in picture in
        // picture), so a quick trip to another app comes back to it still running. `.inactive` changes nothing.
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background: session.background()
            case .active: session.foreground()
            default: break
            }
        }
        .sheet(item: $snapshot) { snapshot in
            KhalaSnapshotSheet(snapshot: snapshot)
        }
        .sheet(isPresented: $showsInfo) {
            KhalaLiveInfoSheet(session: session)
        }
    }

    private func takeSnapshot() {
        guard !isTakingSnapshot else { return }
        isTakingSnapshot = true
        Task { @MainActor in
            let live = await session.snapshot()
            let still: UIImage?
            if let live {
                still = live
            } else {
                still = await session.serverSnapshot()
            }
            isTakingSnapshot = false
            if let still {
                snapshot = KhalaSnapshot(image: still, cameraName: cameraName ?? "")
            }
        }
    }
}

/// The host's handle on the live player on screen: the card's Snapshot button asks it for the live frame.
final class KhalaLiveController: ObservableObject {
    fileprivate weak var session: KhalaWebKitLiveSession?

    /// The frame on screen at the stream's resolution; `nil` when nothing plays or the page cannot read it.
    @MainActor
    func snapshot() async -> UIImage? {
        await session?.snapshot()
    }
}

/// Holds the web view and runs the page: `KhalaLiveStage` decides the lanes, `KhalaWebRTCSignaling` runs the
/// WebRTC lane, the HLS lane is fetched here, `KhalaLiveVisibility` keeps the stream across a short trip away.
/// Main-thread confined: every callback from HAKit, the page or a timer comes back through `post(_:)`, and one that
/// arrives on another thread is moved to main rather than trapping.
///
/// Teardown is idempotent (`invalidate()`, also run by `deinit`): once invalidated nothing reaches the signaling,
/// the page, HAKit or the host again. Build 30.1 crashed right after giving way to HLS; the hand-off is sequenced —
/// page stopped (peer connection closed, media released) and the WebKit callback stack left — before the host is
/// told, and every late callback (script message, evaluate completion, navigation delegate, timer, HAKit) is dropped
/// by the invalidated flag or by the attempt and generation numbers.
final class KhalaWebKitLiveSession: NSObject, ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var didFail = false
    @Published private(set) var path: KhalaLivePath?
    @Published private(set) var isMuted: Bool
    @Published private(set) var isPictureInPicture = false

    let webView: WKWebView

    private static let log = os.Logger(subsystem: "il.co.provizor.khala", category: "live")

    private let server: Server
    private let cameraEntityId: String
    private let scriptHandler: KhalaWeakScriptHandler
    private var signaling = KhalaWebRTCSignaling()
    private var stage: KhalaLiveStage
    private var visibility = KhalaLiveVisibility()
    private var gate: WebRTCServerConnectionGate?
    private var offerSubscription: HACancellable?
    private var socketObserver: NSObjectProtocol?
    private var deadlines: [DispatchWorkItem] = []
    private var cleanupTimer: DispatchWorkItem?
    /// Events that arrived while the effects of another were being performed (an evaluate completion WebKit
    /// calls synchronously, say): handled after it, never inside it.
    private var pendingEvents: [KhalaWebRTCSignaling.Event] = []
    private var isHandling = false
    private var isInvalidated = false
    private var isHandingOff = false
    private var isPageReady = false
    private var isInBackground = false
    private var pendingPoster: String?
    private var posterSource: UIImage?
    /// Bumped for every HLS lane start and stop, so a late answer for an older one is dropped.
    private var hlsGeneration = 0
    private var hlsRequest: DataRequest?
    private var rtcHasAudio = false
    private var rtcCodec: String?
    private var hlsCodec: String?
    private var lastStats: KhalaLiveStats.Sample?
    private var lastFailure: String?

    init(server: Server, cameraEntityId: String, lanes: KhalaLiveLanes, fit: KhalaWebRTCPage.Fit) {
        self.server = server
        self.cameraEntityId = cameraEntityId
        let muted = KhalaLiveEngineStore.isMuted
        self.isMuted = muted
        self.stage = KhalaLiveStage(supported: lanes.streamKinds, muted: muted)

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = true
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
        // Touches belong to the native zoom container around it (`KhalaLiveZoomView`); the page takes none.
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
        cleanupTimer?.cancel()
        gate?.cancel()
        offerSubscription?.cancel()
        hlsRequest?.cancel()
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

    // MARK: - Host

    func start() {
        guard !isInvalidated else { return }
        didFail = false
        apply(stage.start())
    }

    func stop() {
        guard !isInvalidated else { return }
        cleanupTimer?.cancel()
        apply(stage.stop())
        send(.stop)
    }

    func background() {
        guard !isInvalidated else { return }
        isInBackground = true
        perform(visibility.backgrounded(at: Current.date(), isPlaying: !stage.isLoading))
    }

    func foreground() {
        guard !isInvalidated else { return }
        isInBackground = false
        perform(visibility.foregrounded(at: Current.date()))
    }

    func toggleMute() {
        guard !isInvalidated else { return }
        isMuted.toggle()
        KhalaLiveEngineStore.isMuted = isMuted
        evaluate(.setMuted(isMuted))
        apply(stage.setMuted(isMuted))
    }

    func togglePictureInPicture() {
        guard !isInvalidated else { return }
        // Picture in picture plays through the app's audio session; the HLS player sets the same category.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        } catch {
            Self.log.info("audio session category not set for picture in picture")
        }
        evaluate(.togglePictureInPicture)
    }

    /// The still both video elements show until their first frame, as the frontend's `poster`. Sent as a JPEG data
    /// URL (no request from the page), at most 1280 pt wide.
    func setPoster(_ image: UIImage?) {
        guard let image, image !== posterSource, !isInvalidated else { return }
        posterSource = image
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let url = Self.dataURL(for: image)
            DispatchQueue.main.async {
                guard let self, let url, !self.isInvalidated, self.posterSource === image else { return }
                if self.isPageReady {
                    self.evaluate(.setPoster(dataURL: url))
                } else {
                    self.pendingPoster = url
                }
            }
        }
    }

    /// The frame on screen at the stream's own resolution (`window.khala.snapshot()`); `nil` when nothing plays or
    /// the page cannot read it.
    @MainActor
    func snapshot() async -> UIImage? {
        guard !isInvalidated, !isLoading else { return nil }
        let value = await callAsync("return window.khala.snapshot();")
        guard let text = value as? String, text.hasPrefix("data:image/"), let comma = text.firstIndex(of: ","),
              let data = Data(base64Encoded: String(text[text.index(after: comma)...])) else { return nil }
        return UIImage(data: data)
    }

    /// The server's still (`camera_proxy`), when the live frame cannot be had.
    @MainActor
    func serverSnapshot() async -> UIImage? {
        guard let api = Current.api(for: server) else { return nil }
        return try? await api.getCameraSnapshot(cameraEntityID: cameraEntityId).asyncValue()
    }

    /// One reading for the info sheet; rates come from the previous one.
    @MainActor
    func stats() async -> KhalaLiveStats? {
        guard !isInvalidated else { return nil }
        let value = await callAsync("return await window.khala.stats();")
        guard let json = value as? [String: Any], let sample = KhalaLiveStats.Sample(json: json) else { return nil }
        let stats = KhalaLiveStats(sample, previous: lastStats, codec: sample.lane == .hls ? hlsCodec : rtcCodec)
        lastStats = sample
        return stats
    }

    /// Everything the session holds, released once: timers, the gate, the server subscription (closing the
    /// session on the server), the HLS request, the socket observer, the script handler, the navigation delegate
    /// and the page's peer connection and media. Safe to call any number of times.
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
        cleanupTimer?.cancel()
        cleanupTimer = nil
        gate?.cancel()
        gate = nil
        offerSubscription?.cancel()
        offerSubscription = nil
        hlsRequest?.cancel()
        hlsRequest = nil
        if let socketObserver {
            NotificationCenter.default.removeObserver(socketObserver)
            self.socketObserver = nil
        }
        scriptHandler.target = nil
        Self.releasePage(of: webView)
    }

    /// Stops the page's streams and detaches the web view from us. Never touches the session, so `deinit` can use
    /// it.
    private static func releasePage(of webView: WKWebView) {
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: KhalaWebRTCPage.messageHandler)
        webView.evaluateJavaScript("window.khala && (window.khala.stop(), window.khala.hlsStop()); true",
                                   completionHandler: nil)
        webView.stopLoading()
    }

    // MARK: - Stage

    private func apply(_ effects: [KhalaLiveStage.Effect]) {
        for effect in effects {
            guard !isInvalidated else { return }
            switch effect {
            case .startLane(.webRTC):
                rtcHasAudio = false
                send(.start)
            case .stopLane(.webRTC):
                rtcCodec = nil
                send(.stop)
            case .startLane(.hls):
                startHLS()
            case .stopLane(.hls):
                stopHLS()
            case .startLane(.mjpeg), .stopLane(.mjpeg):
                break
            case let .show(kind):
                evaluate(.show(kind))
            case .giveUp:
                handOff(lastFailure ?? "no stream")
            }
        }
        publish()
    }

    /// The loader and the badge follow the lane on screen.
    private func publish() {
        guard !isInvalidated else { return }
        if isLoading != stage.isLoading { isLoading = stage.isLoading }
        let newPath: KhalaLivePath?
        switch (stage.isLoading, stage.front) {
        case (false, .webRTC?): newPath = KhalaLivePath(.webRTC, codec: rtcCodec)
        case (false, .hls?): newPath = KhalaLivePath(.hls, codec: hlsCodec)
        default: newPath = nil
        }
        if newPath != path { path = newPath }
    }

    // MARK: - Visibility

    private func perform(_ action: KhalaLiveVisibility.Action) {
        switch action {
        case .keep:
            break
        case let .armCleanup(token, delay):
            cleanupTimer?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self, !self.isInvalidated else { return }
                self.perform(self.visibility.cleanupDeadline(token: token))
            }
            cleanupTimer = item
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        case .cleanUp:
            cleanupTimer?.cancel()
            Self.log.info("\(self.cameraEntityId, privacy: .public): hidden, stream released")
            apply(stage.stop())
            send(.stop)
        case .resume:
            start()
        case .restart:
            apply(stage.stop())
            send(.stop)
            start()
        }
    }

    // MARK: - HLS lane

    /// `ha-hls-player` `_getStreamUrlFromEntityId` + `_startHls`: `camera/stream` for the playlist, the master
    /// playlist fetched and parsed (`KhalaHLSPlaylist`), its report to the stage, then the page plays it. Fetched
    /// through the app's own session, which carries any client certificate or security exception.
    private func startHLS() {
        hlsGeneration += 1
        let generation = hlsGeneration
        hlsRequest?.cancel()
        guard let api = Current.api(for: server) else {
            hlsFailed(generation, "no server")
            return
        }
        api.connection.send(.init(
            type: .webSocket("camera/stream"),
            data: ["entity_id": cameraEntityId]
        )) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, generation == self.hlsGeneration, !self.isInvalidated else { return }
                switch result {
                case let .success(data):
                    guard case let .dictionary(json) = data, let path = json["url"] as? String else {
                        self.hlsFailed(generation, "no playlist")
                        return
                    }
                    Task { @MainActor [weak self] in
                        guard let base = await api.server.activeURL() else {
                            self?.hlsFailed(generation, "no server URL")
                            return
                        }
                        self?.fetchMaster(CameraStreamHLSView.playlistURL(baseURL: base, hlsPath: path),
                                          api: api, generation: generation)
                    }
                case let .failure(error):
                    self.hlsFailed(generation, "stream refused: \(Self.message(of: error))")
                }
            }
        }
    }

    private func fetchMaster(_ url: URL, api: HomeAssistantAPI, generation: Int) {
        guard generation == hlsGeneration, !isInvalidated else { return }
        hlsRequest = api.manager.request(url).validate().responseString(queue: .main) { [weak self] response in
            guard let self, generation == self.hlsGeneration, !self.isInvalidated else { return }
            self.hlsRequest = nil
            switch response.result {
            case let .success(master):
                let playlist = KhalaHLSPlaylist(master: master, url: url)
                self.hlsCodec = playlist.videoCodec
                // `_reportStreams` comes before the player starts, as in the frontend.
                self.apply(self.stage.report(.hls, playlist.report))
                guard self.stage.running.contains(.hls), generation == self.hlsGeneration else { return }
                self.evaluate(.hlsStart(url: playlist.playlistURL.absoluteString))
            case let .failure(error):
                self.hlsFailed(generation, "playlist: \(error.responseCode.map(String.init) ?? "network")")
            }
        }
    }

    private func stopHLS() {
        hlsGeneration += 1
        hlsRequest?.cancel()
        hlsRequest = nil
        evaluate(.hlsStop)
    }

    private func hlsFailed(_ generation: Int, _ reason: String) {
        guard generation == hlsGeneration, !isInvalidated else { return }
        let text = KhalaLiveFailure.redacted(reason)
        Self.log.info("\(self.cameraEntityId, privacy: .public): HLS lane out: \(text, privacy: .public)")
        lastFailure = lastFailure ?? "HLS: \(text)"
        apply(stage.report(.hls, .failed))
    }

    // MARK: - Signaling

    private func send(_ event: KhalaWebRTCSignaling.Event) {
        guard Thread.isMainThread else {
            post(event)
            return
        }
        guard !isInvalidated else { return }
        if event == .socketLost, visibility.isHidden {
            // Gone while away: the server closed the session with the socket; resume fresh on return.
            perform(visibility.socketLost())
            return
        }
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
            if signaling.phase != .playing, stage.playing.contains(.webRTC) {
                _ = stage.setPlaying(.webRTC, false)
                publish()
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
            Self.log.info("\(self.cameraEntityId, privacy: .public): WebRTC first frame")
            // `ha-web-rtc-player` `_loadedData` reports its streams; then the selection shows it.
            apply(stage.report(.webRTC, KhalaStreamReport(hasAudio: rtcHasAudio, hasVideo: true)))
            _ = stage.setPlaying(.webRTC, true)
            publish()
        case let .codec(name):
            rtcCodec = name
            publish()

        case let .fallBack(failure):
            webRTCLaneFailed(failure)
        }
    }

    /// The WebRTC lane is out (no answer, failed ICE, a JavaScript error, no frame in time, a dropped stream that
    /// could not be rebuilt). Recorded for the fallback memory, then reported to the stage, which shows HLS when it
    /// has it or gives way to the host.
    private func webRTCLaneFailed(_ failure: KhalaLiveFailure) {
        let reason = failure.logDescription
        Self.log.error("\(self.cameraEntityId, privacy: .public): WebKit WebRTC lane out: \(reason, privacy: .public)")
        Current.Log.info("Khala live: \(cameraEntityId) WebKit WebRTC lane out (\(reason))")
        KhalaLiveEngineStore.memory.record(failure, cameraEntityId: cameraEntityId)
        lastFailure = reason
        rtcCodec = nil
        apply(stage.report(.webRTC, .failed))
    }

    /// Gives way to the next player. The page's lanes are stopped first; the host is told only once that stop has
    /// run in the page (its completion, or half a second at most) and on a fresh turn of the main queue, so HLS's
    /// AVPlayer and audio session are never set up while WebKit is still tearing its peer connection down, and
    /// never from inside a WebKit callback.
    private func handOff(_ reason: String) {
        guard !isHandingOff else { return }
        isHandingOff = true
        Self.log.error("\(self.cameraEntityId, privacy: .public): WebKit live gave way: \(reason, privacy: .public)")
        Current.Log.info("Khala live: \(cameraEntityId) WebKit live gave way (\(reason))")
        send(.stop)
        evaluate(.hlsStop)

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
            if case .hlsStart = command {
                self.hlsFailed(self.hlsGeneration, "page refused the playlist (\(code))")
                return
            }
            guard command.isEssential else {
                Self.log.info("\(self.cameraEntityId, privacy: .public): page call failed (\(code)), ignored")
                return
            }
            // `window.khala` missing means the page is not there; anything else threw inside it. The signaling
            // ignores this once the stream is stopped or has already given way.
            send(.page(.error(message: "evaluate failed (\(code))")))
        }
    }

    /// `callAsyncJavaScript` in the page's world; `nil` on any failure.
    @MainActor
    private func callAsync(_ body: String) async -> Any? {
        guard !isInvalidated else { return nil }
        return await withCheckedContinuation { continuation in
            webView.callAsyncJavaScript(body, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case let .success(value): continuation.resume(returning: value)
                case .failure: continuation.resume(returning: nil)
                }
            }
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
        case .ready:
            isPageReady = true
            evaluate(.setMuted(isMuted))
            if let pendingPoster {
                evaluate(.setPoster(dataURL: pendingPoster))
                self.pendingPoster = nil
            }
        case let .note(text):
            let note = KhalaLiveFailure.redacted(text)
            Self.log.info("\(camera, privacy: .public): page: \(note, privacy: .public)")
        case let .ice(state):
            Self.log.info("\(camera, privacy: .public): ICE \(state, privacy: .public)")
        case let .error(text):
            let error = KhalaLiveFailure.redacted(text)
            Self.log.error("\(camera, privacy: .public): page error: \(error, privacy: .public)")
        case .audio:
            rtcHasAudio = true
            if signaling.phase == .playing {
                apply(stage.report(.webRTC, KhalaStreamReport(hasAudio: true, hasVideo: true)))
            }
            return
        case let .hls(.frame(width, height)):
            Self.log.info("\(camera, privacy: .public): HLS first frame \(width)x\(height)")
            _ = stage.setPlaying(.hls, true)
            publish()
            return
        case let .hls(.error(text)):
            hlsFailed(hlsGeneration, KhalaLiveFailure.redacted(text))
            return
        case let .presentation(mode):
            let active = mode == "picture-in-picture"
            if active != isPictureInPicture { isPictureInPicture = active }
            perform(visibility.pictureInPicture(
                active, inBackground: isInBackground, at: Current.date(), isPlaying: !stage.isLoading
            ))
            return
        case .poster:
            return
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

    private static func dataURL(for image: UIImage) -> String? {
        let maxWidth: CGFloat = 1280
        var source = image
        let width = image.size.width * image.scale
        if width > maxWidth {
            let size = CGSize(width: maxWidth, height: (image.size.height * image.scale) * maxWidth / width)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            source = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        guard let data = source.jpegData(compressionQuality: 0.8) else { return nil }
        return "data:image/jpeg;base64," + data.base64EncodedString()
    }
}

/// The app session's live-engine state: the hidden setting (`KhalaLiveEngine`, App settings → General → Khala),
/// the per-camera fallback memory and the remembered mute. Main thread only.
enum KhalaLiveEngineStore {
    static var memory = KhalaLiveFallbackMemory()

    static let mutedKey = "khala.liveMuted"

    static var engine: KhalaLiveEngine {
        get { KhalaLiveEngine(stored: UserDefaults.standard.string(forKey: KhalaLiveEngine.defaultsKey)) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: KhalaLiveEngine.defaultsKey) }
    }

    /// The live player's mute, remembered across cameras and launches; muted until first unmuted.
    static var isMuted: Bool {
        get { UserDefaults.standard.object(forKey: mutedKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: mutedKey) }
    }

    /// The camera's player plan with the engine setting and the memory applied (both hosts use it).
    static func plan(_ players: [CameraPlayerType], cameraEntityId: String) -> [CameraPlayerType] {
        let skips = memory.skipsWebKit(cameraEntityId: cameraEntityId)
        let planned = engine.plan(players, webRTC: .webRTC, hls: .hls, webKitFailedRepeatedly: skips)
        if planned != players {
            Current.Log.info("Khala live: \(cameraEntityId) skips the WebKit page (engine \(engine.rawValue))")
        }
        return planned
    }

    /// What the WebKit page runs for this camera (its `.webRTC` slot in the plan), from the camera's own plan.
    static func lanes(_ players: [CameraPlayerType], cameraEntityId: String) -> KhalaLiveLanes {
        let skips = memory.skipsWebKit(cameraEntityId: cameraEntityId)
        let lanes = engine.lanes(players, webRTC: .webRTC, hls: .hls, webKitFailedRepeatedly: skips)
        if !lanes.webRTC, players.contains(.webRTC) {
            Current.Log.info("Khala live: \(cameraEntityId) runs the WebKit page on HLS only")
        }
        return lanes
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

    /// The HLS lane loads from the server: a client certificate or a security exception is answered as the app's
    /// main web view answers it.
    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let result = server.info.connection.evaluate(challenge)
        completionHandler(result.0, result.1)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        send(.page(.error(message: "web content process ended")))
        hlsFailed(hlsGeneration, "web content process ended")
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
