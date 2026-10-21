import Foundation

// The WebKit live player's signaling, Foundation-only so the rules run on Linux (`Tools/Khala/linux-check.sh`).
//
// Message shapes, checked against the sources Nir's server runs (HA 2026.10.2, frontend 20260930.4) and against
// the server itself:
// - `camera/webrtc/get_client_config {entity_id}` → `{configuration: RTCConfiguration, dataChannel?}`
//   (core `components/camera/webrtc.py` `ws_get_client_config` / `WebRTCClientConfiguration.to_frontend_dict`);
// - `camera/webrtc/offer {entity_id, offer}` is a SUBSCRIPTION: an empty result, then events
//   `{type: "session", session_id}`, `{type: "answer", answer}`, `{type: "candidate", candidate: {candidate,
//   sdpMid?, sdpMLineIndex?}}` and `{type: "error", code, message}` (`ws_webrtc_offer`, `WebRTCMessage.as_dict`);
//   unsubscribing closes the session (`camera.close_webrtc_session`);
// - `camera/webrtc/candidate {entity_id, session_id, candidate: RTCIceCandidateInit}` (`ws_candidate`), sent only
//   once the session id is known (frontend `ha-web-rtc-player.ts` `_handleIceCandidate`).

/// An ICE candidate as both Home Assistant and the browser spell it (`RTCIceCandidateInit`).
struct KhalaIceCandidate: Equatable {
    let candidate: String
    let sdpMid: String?
    let sdpMLineIndex: Int?
    let usernameFragment: String?

    init(candidate: String, sdpMid: String? = nil, sdpMLineIndex: Int? = nil, usernameFragment: String? = nil) {
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
        self.usernameFragment = usernameFragment
    }

    /// Reads a server event's `candidate` or the page's `RTCIceCandidate.toJSON()`. `nil` for the empty
    /// end-of-candidates marker, which needs no forwarding.
    init?(json: [String: Any]) {
        guard let candidate = json["candidate"] as? String, !candidate.isEmpty else { return nil }
        self.candidate = candidate
        self.sdpMid = json["sdpMid"] as? String
        self.sdpMLineIndex = KhalaJSON.int(json["sdpMLineIndex"])
        self.usernameFragment = json["usernameFragment"] as? String
    }

    /// The `RTCIceCandidateInit` to send. A candidate needs an `sdpMid` or an `sdpMLineIndex` to be accepted at
    /// all; when the other side sent neither, `sdpMid` is "0", exactly as the frontend does.
    var json: [String: Any] {
        var json: [String: Any] = ["candidate": candidate]
        if let sdpMid { json["sdpMid"] = sdpMid }
        if let sdpMLineIndex { json["sdpMLineIndex"] = sdpMLineIndex }
        if sdpMid == nil, sdpMLineIndex == nil { json["sdpMid"] = "0" }
        if let usernameFragment { json["usernameFragment"] = usernameFragment }
        return json
    }
}

/// One event of the `camera/webrtc/offer` subscription.
enum KhalaWebRTCServerEvent: Equatable {
    case session(id: String)
    case answer(sdp: String)
    /// `nil`: the end-of-candidates marker.
    case candidate(KhalaIceCandidate?)
    case error(code: String?, message: String?)
    case unknown(type: String)

    init?(json: [String: Any]) {
        guard let type = json["type"] as? String else { return nil }
        switch type {
        case "session":
            guard let id = json["session_id"] as? String else { return nil }
            self = .session(id: id)
        case "answer":
            guard let sdp = json["answer"] as? String else { return nil }
            self = .answer(sdp: sdp)
        case "candidate":
            self = .candidate((json["candidate"] as? [String: Any]).flatMap(KhalaIceCandidate.init(json:)))
        case "error":
            self = .error(code: json["code"] as? String, message: json["message"] as? String)
        default:
            self = .unknown(type: type)
        }
    }
}

/// What the page posts to native (`KhalaWebRTCPage`).
enum KhalaWebRTCPageMessage: Equatable {
    case ready
    case offer(sdp: String)
    case candidate(KhalaIceCandidate)
    /// `RTCPeerConnection.iceConnectionState`.
    case ice(state: String)
    /// The first decoded frame.
    case frame(width: Int, height: Int)
    /// The inbound video codec, from `getStats()`: "video/H265".
    case codec(mimeType: String)
    case error(message: String)

    /// `WKScriptMessage.body`: a dictionary with a `type`.
    init?(body: Any) {
        guard let json = body as? [String: Any], let type = json["type"] as? String else { return nil }
        switch type {
        case "ready":
            self = .ready
        case "offer":
            guard let sdp = json["sdp"] as? String, !sdp.isEmpty else { return nil }
            self = .offer(sdp: sdp)
        case "candidate":
            guard let candidate = (json["candidate"] as? [String: Any]).flatMap(KhalaIceCandidate.init(json:)) else {
                return nil
            }
            self = .candidate(candidate)
        case "ice":
            guard let state = json["state"] as? String else { return nil }
            self = .ice(state: state)
        case "frame":
            self = .frame(width: KhalaJSON.int(json["width"]) ?? 0, height: KhalaJSON.int(json["height"]) ?? 0)
        case "codec":
            guard let mimeType = json["mimeType"] as? String else { return nil }
            self = .codec(mimeType: mimeType)
        case "error":
            self = .error(message: json["message"] as? String ?? "")
        default:
            return nil
        }
    }
}

/// What native tells the page, as the JavaScript to evaluate. Every argument goes in as JSON, so an SDP or a
/// candidate can never break out of the call.
enum KhalaWebRTCPageCommand: Equatable {
    case start(KhalaWebRTCClientConfig)
    case answer(sdp: String)
    case candidate(KhalaIceCandidate)
    case setMuted(Bool)
    case stop

    var javaScript: String {
        switch self {
        case let .start(config):
            return "window.khala.start(\(config.pageJSON));"
        case let .answer(sdp):
            return "window.khala.answer(\(KhalaJSON.literal(sdp)));"
        case let .candidate(candidate):
            return "window.khala.candidate(\(KhalaJSON.object(candidate.json)));"
        case let .setMuted(muted):
            return "window.khala.setMuted(\(muted ? "true" : "false"));"
        case .stop:
            return "window.khala.stop();"
        }
    }
}

/// The server's answer to `camera/webrtc/get_client_config`, kept as the JSON the page hands to
/// `new RTCPeerConnection(...)`. It can hold TURN credentials, so it is never logged.
struct KhalaWebRTCClientConfig: Equatable {
    /// `{"configuration": {...}, "dataChannel"?: "..."}`.
    let pageJSON: String

    /// The server's answer. A configuration with no ICE servers gets the fallback ones, as the native player does.
    init(json: [String: Any], fallbackICEServers: [String]) {
        var configuration = json["configuration"] as? [String: Any] ?? [:]
        if (configuration["iceServers"] as? [Any])?.isEmpty ?? true {
            configuration["iceServers"] = [["urls": fallbackICEServers]]
        }
        var page: [String: Any] = ["configuration": configuration]
        if let dataChannel = json["dataChannel"] as? String {
            page["dataChannel"] = dataChannel
        }
        self.pageJSON = KhalaJSON.object(page)
    }

    /// When `get_client_config` failed for a reason other than the camera having no WebRTC: the frontend's
    /// default STUN servers.
    static func fallback(iceServers: [String]) -> KhalaWebRTCClientConfig {
        KhalaWebRTCClientConfig(json: [:], fallbackICEServers: iceServers)
    }
}

/// Why WebRTC gave way to the next player.
enum KhalaLiveFailure: Equatable {
    /// The camera has no WebRTC stream type (core's `require_webrtc_support`).
    case unsupported
    /// The server could not be reached over the websocket in time, or refused us.
    case noServer
    /// The offer was rejected or the session reported an error.
    case signaling(String?)
    /// No first frame in time (no answer, ICE never connected, or a codec WebKit cannot decode).
    case timeout
    /// ICE failed, or a dropped stream could not be brought back.
    case ice
    /// The page's JavaScript threw, or its web content process died.
    case page(String)

    /// Core reports "no WebRTC" and "stream could not be set up" under one error code; the message separates them
    /// (same test as `WebRTCViewPlayerViewModel.isWebRTCUnsupported`).
    static func isUnsupported(message: String) -> Bool {
        message.contains("does not support WebRTC") || message.contains("frontend_stream_types")
    }
}

/// The live player's signaling as a state machine: events in, effects out, no I/O. `KhalaWebKitLivePlayer` performs
/// the effects (websocket, page, timers) and feeds what comes back in as events.
///
/// Every attempt has a number; callbacks carry the number of the attempt that asked, so an answer to a torn-down
/// attempt can never touch the one on screen.
struct KhalaWebRTCSignaling {
    struct Timing: Equatable {
        /// Start of signaling (server reachable) to first decoded frame. Locally the whole negotiation takes well
        /// under a second against go2rtc, so silence this long means WebRTC is not going to play.
        var firstFrame: TimeInterval = 6
        /// A playing stream whose ICE dropped gets this long to come back by itself before it is rebuilt.
        var disconnectedGrace: TimeInterval = 4
        /// How long to wait for the server's websocket to be usable before giving up on WebRTC.
        var serverWait: TimeInterval = 20
        /// Rebuilds of a stream that was playing before giving up and falling back.
        var maxRetries: Int = 2

        static let production = Timing()
    }

    enum Phase: Equatable {
        case idle
        /// Waiting for the server's websocket to be usable.
        case waitingForServer
        /// Asking for the client configuration.
        case configuring
        /// The page is creating its peer connection and offer.
        case offering
        /// The offer is out; session, answer and candidates flow.
        case negotiating
        case playing
        /// Stopped while the app is in the background; resumes when it returns.
        case suspended
        case failed(KhalaLiveFailure)
        case stopped
    }

    enum Event: Equatable {
        case start
        case stop
        case backgrounded
        case foregrounded
        case serverReady(attempt: Int)
        case serverUnusable(attempt: Int)
        /// `nil` config: the request failed for a reason other than "no WebRTC".
        case clientConfig(attempt: Int, KhalaWebRTCClientConfig?)
        case clientConfigUnsupported(attempt: Int)
        case offerRejected(attempt: Int, message: String)
        case server(attempt: Int, KhalaWebRTCServerEvent)
        case page(KhalaWebRTCPageMessage)
        /// The websocket left ready while a stream depended on it. Core closes the session with the socket, and
        /// HAKit would resend the old offer on reconnect, so the attempt is rebuilt instead.
        case socketLost
        case serverWaitDeadline(attempt: Int)
        case firstFrameDeadline(attempt: Int)
        case recoveryDeadline(attempt: Int)
    }

    enum Effect: Equatable {
        case waitForServer(attempt: Int, freshConnection: Bool)
        case fetchClientConfig(attempt: Int)
        case subscribeOffer(attempt: Int, sdp: String)
        case sendCandidate(sessionId: String, KhalaIceCandidate)
        /// Cancel the offer subscription (closes the session on the server).
        case unsubscribe
        case page(KhalaWebRTCPageCommand)
        case armFirstFrameDeadline(attempt: Int, after: TimeInterval)
        case armServerWaitDeadline(attempt: Int, after: TimeInterval)
        case armRecoveryDeadline(attempt: Int, after: TimeInterval)
        case cancelDeadlines
        /// The first frame is on screen.
        case playing
        /// The decoded codec's display name ("H.265").
        case codec(String)
        /// Give up on WebRTC: the host moves on to HLS, then MJPEG.
        case fallBack(KhalaLiveFailure)
    }

    let timing: Timing
    private(set) var phase: Phase = .idle
    private(set) var attempt = 0
    private(set) var isPageLoaded = false
    private(set) var sessionId: String?
    private(set) var retries = 0
    private var config: KhalaWebRTCClientConfig?
    private var pendingCandidates: [KhalaIceCandidate] = []
    private var hasPlayed = false
    /// Set after a lost socket, so the next wait ignores a connection that still claims to be ready.
    private var needsFreshConnection = false

    init(timing: Timing = .production) {
        self.timing = timing
    }

    var isActive: Bool {
        switch phase {
        case .waitingForServer, .configuring, .offering, .negotiating, .playing: return true
        default: return false
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .start:
            switch phase {
            case .idle, .stopped, .suspended:
                retries = 0
                hasPlayed = false
                return begin()
            default:
                return []
            }

        case .stop:
            guard phase != .stopped else { return [] }
            let effects = tearDown()
            phase = .stopped
            return effects

        case .backgrounded:
            guard isActive else { return [] }
            let effects = tearDown()
            phase = .suspended
            return effects

        case .foregrounded:
            guard phase == .suspended else { return [] }
            retries = 0
            return begin()

        case let .serverReady(n):
            guard n == attempt, phase == .waitingForServer else { return [] }
            needsFreshConnection = false
            phase = .configuring
            return [
                .cancelDeadlines,
                .armFirstFrameDeadline(attempt: attempt, after: timing.firstFrame),
                .fetchClientConfig(attempt: attempt),
            ]

        case let .serverUnusable(n):
            guard n == attempt, phase == .waitingForServer else { return [] }
            return fail(.noServer)

        case let .clientConfig(n, received):
            guard n == attempt, phase == .configuring else { return [] }
            config = received ?? .fallback(iceServers: Self.fallbackICEServers)
            phase = .offering
            return startPageIfReady()

        case let .clientConfigUnsupported(n):
            guard n == attempt, phase == .configuring else { return [] }
            return fail(.unsupported)

        case let .offerRejected(n, message):
            guard n == attempt, phase == .negotiating else { return [] }
            return fail(KhalaLiveFailure.isUnsupported(message: message) ? .unsupported : .signaling(message))

        case let .server(n, serverEvent):
            guard n == attempt, phase == .negotiating || phase == .playing else { return [] }
            return handle(serverEvent)

        case let .page(message):
            return handle(message)

        case .socketLost:
            guard phase == .negotiating || phase == .playing || phase == .offering || phase == .configuring else {
                return []
            }
            needsFreshConnection = true
            return tearDown() + begin()

        case let .serverWaitDeadline(n):
            guard n == attempt, phase == .waitingForServer else { return [] }
            return fail(.noServer)

        case let .firstFrameDeadline(n):
            guard n == attempt, isActive, phase != .playing else { return [] }
            return fail(.timeout)

        case let .recoveryDeadline(n):
            guard n == attempt, phase == .playing else { return [] }
            return retry()
        }
    }

    private mutating func handle(_ serverEvent: KhalaWebRTCServerEvent) -> [Effect] {
        switch serverEvent {
        case let .session(id):
            sessionId = id
            let flushed = pendingCandidates.map { Effect.sendCandidate(sessionId: id, $0) }
            pendingCandidates.removeAll()
            return flushed
        case let .answer(sdp):
            return [.page(.answer(sdp: sdp))]
        case let .candidate(candidate):
            return candidate.map { [.page(.candidate($0))] } ?? []
        case let .error(_, message):
            if let message, KhalaLiveFailure.isUnsupported(message: message) {
                return fail(.unsupported)
            }
            return fail(.signaling(message))
        case .unknown:
            return []
        }
    }

    private mutating func handle(_ message: KhalaWebRTCPageMessage) -> [Effect] {
        switch message {
        case .ready:
            // The page's script ran: from now on it takes commands. It stays loaded across attempts.
            isPageLoaded = true
            return startPageIfReady()
        case let .offer(sdp):
            guard phase == .offering else { return [] }
            phase = .negotiating
            return [.subscribeOffer(attempt: attempt, sdp: sdp)]
        case let .candidate(candidate):
            guard phase == .negotiating || phase == .playing else { return [] }
            if let sessionId {
                return [.sendCandidate(sessionId: sessionId, candidate)]
            }
            pendingCandidates.append(candidate)
            return []
        case let .ice(state):
            return handleICE(state)
        case .frame:
            guard phase == .negotiating else { return [] }
            phase = .playing
            hasPlayed = true
            return [.cancelDeadlines, .playing]
        case let .codec(mimeType):
            guard phase == .playing else { return [] }
            return [.codec(Self.codecName(mimeType: mimeType))]
        case let .error(text):
            guard isActive else { return [] }
            return fail(.page(text))
        }
    }

    private mutating func handleICE(_ state: String) -> [Effect] {
        switch (phase, state) {
        case (.negotiating, "failed"):
            // Before any frame: nothing to rescue, go to the next player now rather than wait out the deadline.
            return fail(.ice)
        case (.playing, "connected"), (.playing, "completed"):
            retries = 0
            return [.cancelDeadlines]
        case (.playing, "disconnected"):
            return [.armRecoveryDeadline(attempt: attempt, after: timing.disconnectedGrace)]
        case (.playing, "failed"), (.playing, "closed"):
            return retry()
        default:
            return []
        }
    }

    /// A stream that played and then broke is rebuilt (fresh session) before WebRTC is given up on.
    private mutating func retry() -> [Effect] {
        guard retries < timing.maxRetries else { return fail(.ice) }
        retries += 1
        return tearDown() + begin()
    }

    private mutating func begin() -> [Effect] {
        attempt += 1
        phase = .waitingForServer
        sessionId = nil
        config = nil
        pendingCandidates.removeAll()
        return [
            .armServerWaitDeadline(attempt: attempt, after: timing.serverWait),
            .waitForServer(attempt: attempt, freshConnection: needsFreshConnection),
        ]
    }

    private mutating func startPageIfReady() -> [Effect] {
        guard phase == .offering, isPageLoaded, let config else { return [] }
        return [.page(.start(config))]
    }

    /// Everything an attempt holds: the subscription (and so the server's session), the page's peer connection
    /// and the timers.
    private mutating func tearDown() -> [Effect] {
        sessionId = nil
        config = nil
        pendingCandidates.removeAll()
        return [.cancelDeadlines, .unsubscribe, .page(.stop)]
    }

    private mutating func fail(_ failure: KhalaLiveFailure) -> [Effect] {
        let effects = tearDown()
        phase = .failed(failure)
        return effects + [.fallBack(failure)]
    }

    /// The frontend's default STUN servers (`AppConstants.WebRTC.iceServers`), for a server that sends none.
    static let fallbackICEServers = ["stun:stun.home-assistant.io:80", "stun:stun.home-assistant.io:3478"]

    /// "video/H265" → "H.265", for the LIVE badge.
    static func codecName(mimeType: String) -> String {
        let name = mimeType.split(separator: "/").last.map(String.init) ?? mimeType
        switch name.uppercased() {
        case "H265", "HEVC": return "H.265"
        case "H264", "AVC": return "H.264"
        default: return name.uppercased()
        }
    }
}

/// Which way the live card is actually playing, for its badge: "WebRTC · H.265", "HLS", "MJPEG".
struct KhalaLivePath: Equatable {
    enum Transport: Equatable {
        case webRTC
        case hls
        case mjpeg
    }

    let transport: Transport
    /// The decoded codec's display name, when known (WebRTC reads it from `getStats()`).
    let codec: String?

    init(_ transport: Transport, codec: String? = nil) {
        self.transport = transport
        self.codec = codec
    }

    var label: String {
        let name: String
        switch transport {
        case .webRTC: name = "WebRTC"
        case .hls: name = "HLS"
        case .mjpeg: name = "MJPEG"
        }
        return ([name] + (codec.map { [$0] } ?? [])).joined(separator: " · ")
    }
}

/// JSON helpers shared by the signaling types.
enum KhalaJSON {
    /// A JSON number as an Int, whether it arrived as Int, Double or NSNumber.
    static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    /// A JSON object, keys sorted so the output is stable.
    static func object(_ value: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// A JSON string literal, safe to splice into JavaScript.
    static func literal(_ value: String) -> String {
        let wrapped = object(["v": value])
        // {"v":"..."} → "..."
        guard wrapped.hasPrefix("{\"v\":"), wrapped.hasSuffix("}") else { return "\"\"" }
        return String(wrapped.dropFirst(5).dropLast())
    }
}
