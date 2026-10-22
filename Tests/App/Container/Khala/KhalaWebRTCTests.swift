import Foundation
@testable import HomeAssistant
import Testing

/// The WebKit live player's signaling (`KhalaWebRTCSignaling`) and the messages it maps. Shapes follow HA core
/// `components/camera/webrtc.py` and the frontend's `ha-web-rtc-player.ts`; addresses are documentation ranges.
struct KhalaWebRTCMessageTests {
    private let hostCandidate = "candidate:1 1 udp 2130706431 192.0.2.10 8555 typ host"

    @Test func serverEventsDecode() {
        #expect(KhalaWebRTCServerEvent(json: ["type": "session", "session_id": "01SESSION"]) == .session(id: "01SESSION"))
        #expect(KhalaWebRTCServerEvent(json: ["type": "answer", "answer": "v=0\r\n"]) == .answer(sdp: "v=0\r\n"))
        #expect(KhalaWebRTCServerEvent(json: [
            "type": "candidate", "candidate": ["candidate": hostCandidate, "sdpMLineIndex": 1],
        ]) == .candidate(KhalaIceCandidate(candidate: hostCandidate, sdpMLineIndex: 1)))
        #expect(KhalaWebRTCServerEvent(json: ["type": "candidate", "candidate": ["candidate": ""]]) == .candidate(nil))
        #expect(KhalaWebRTCServerEvent(json: ["type": "error", "code": "webrtc_offer_failed", "message": "boom"])
            == .error(code: "webrtc_offer_failed", message: "boom"))
        #expect(KhalaWebRTCServerEvent(json: ["type": "later"]) == .unknown(type: "later"))
        #expect(KhalaWebRTCServerEvent(json: ["type": "session"]) == nil)
        #expect(KhalaWebRTCServerEvent(json: [:]) == nil)
    }

    @Test func candidateKeepsWhatWasSentAndDefaultsSdpMidLikeTheFrontend() {
        let indexed = KhalaIceCandidate(json: ["candidate": hostCandidate, "sdpMLineIndex": 1.0])
        #expect(indexed?.sdpMLineIndex == 1)
        #expect(indexed?.json["sdpMid"] == nil)
        #expect(indexed?.json["sdpMLineIndex"] as? Int == 1)

        let bare = KhalaIceCandidate(candidate: hostCandidate)
        #expect(bare.json["sdpMid"] as? String == "0")

        let page = KhalaIceCandidate(json: [
            "candidate": hostCandidate, "sdpMid": "1", "sdpMLineIndex": 1, "usernameFragment": "abcd",
        ])
        #expect(page?.json["sdpMid"] as? String == "1")
        #expect(page?.json["usernameFragment"] as? String == "abcd")
        #expect(KhalaIceCandidate(json: ["candidate": ""]) == nil)
        #expect(KhalaIceCandidate(json: ["sdpMid": "0"]) == nil)
    }

    @Test func pageMessagesDecode() {
        #expect(KhalaWebRTCPageMessage(body: ["type": "ready"]) == .ready)
        #expect(KhalaWebRTCPageMessage(body: ["type": "offer", "sdp": "v=0"]) == .offer(sdp: "v=0"))
        #expect(KhalaWebRTCPageMessage(body: ["type": "offer", "sdp": ""]) == nil)
        #expect(KhalaWebRTCPageMessage(body: ["type": "candidate", "candidate": ["candidate": hostCandidate, "sdpMid": "0"]])
            == .candidate(KhalaIceCandidate(candidate: hostCandidate, sdpMid: "0")))
        #expect(KhalaWebRTCPageMessage(body: ["type": "ice", "state": "connected"]) == .ice(state: "connected"))
        #expect(KhalaWebRTCPageMessage(body: ["type": "frame", "width": 2688, "height": 1520.0])
            == .frame(width: 2688, height: 1520))
        #expect(KhalaWebRTCPageMessage(body: ["type": "codec", "mimeType": "video/H265"]) == .codec(mimeType: "video/H265"))
        #expect(KhalaWebRTCPageMessage(body: ["type": "error", "message": "offer: x"]) == .error(message: "offer: x"))
        #expect(KhalaWebRTCPageMessage(body: ["type": "nope"]) == nil)
        #expect(KhalaWebRTCPageMessage(body: "text") == nil)
    }

    @Test func commandsAreJSONSoNothingBreaksOutOfTheCall() {
        let sdp = "v=0\r\na=x:\"quoted\"</script>');alert(1)//"
        let script = KhalaWebRTCPageCommand.answer(sdp: sdp).javaScript
        #expect(script.hasPrefix("window.khala.answer(\""))
        #expect(script.hasSuffix("\");"))
        #expect(!script.contains("\r\n"))
        #expect(script.contains("\\\"quoted\\\""))
        let argument = String(script.dropFirst("window.khala.answer(".count).dropLast(2))
        let decoded = try? JSONSerialization.jsonObject(with: Data("[\(argument)]".utf8)) as? [String]
        #expect(decoded == [sdp])

        #expect(KhalaWebRTCPageCommand.setMuted(false).javaScript == "window.khala.setMuted(false);")
        #expect(KhalaWebRTCPageCommand.stop.javaScript == "window.khala.stop();")
        let candidate = KhalaWebRTCPageCommand.candidate(KhalaIceCandidate(candidate: hostCandidate)).javaScript
        #expect(candidate == "window.khala.candidate({\"candidate\":\"\(hostCandidate)\",\"sdpMid\":\"0\"});")
    }

    @Test func clientConfigPassesTheServersConfigurationThrough() throws {
        let config = KhalaWebRTCClientConfig(json: [
            "configuration": ["iceServers": [["urls": ["stun:stun.example.org:3478"]]]],
            "dataChannel": "dataSendChannel",
        ], fallbackICEServers: KhalaWebRTCSignaling.fallbackICEServers)
        let page = try #require(
            try JSONSerialization.jsonObject(with: Data(config.pageJSON.utf8)) as? [String: Any]
        )
        #expect(page["dataChannel"] as? String == "dataSendChannel")
        let servers = (page["configuration"] as? [String: Any])?["iceServers"] as? [[String: Any]]
        #expect(servers?.first?["urls"] as? [String] == ["stun:stun.example.org:3478"])
    }

    @Test func clientConfigWithoutServersGetsTheFrontendDefaults() throws {
        for config in [
            KhalaWebRTCClientConfig(json: ["configuration": ["iceServers": []]], fallbackICEServers: ["stun:a"]),
            KhalaWebRTCClientConfig.fallback(iceServers: ["stun:a"]),
        ] {
            let page = try #require(
                try JSONSerialization.jsonObject(with: Data(config.pageJSON.utf8)) as? [String: Any]
            )
            let servers = (page["configuration"] as? [String: Any])?["iceServers"] as? [[String: Any]]
            #expect(servers?.first?["urls"] as? [String] == ["stun:a"])
            #expect(page["dataChannel"] == nil)
        }
    }

    @Test func codecNamesAndBadge() {
        #expect(KhalaWebRTCSignaling.codecName(mimeType: "video/H265") == "H.265")
        #expect(KhalaWebRTCSignaling.codecName(mimeType: "video/H264") == "H.264")
        #expect(KhalaWebRTCSignaling.codecName(mimeType: "video/VP8") == "VP8")
        #expect(KhalaWebRTCSignaling.codecName(mimeType: "video/av1") == "AV1")
        #expect(KhalaLivePath(.webRTC, codec: "H.265").label == "WebRTC · H.265")
        #expect(KhalaLivePath(.webRTC).label == "WebRTC")
        #expect(KhalaLivePath(.hls).label == "HLS")
        #expect(KhalaLivePath(.mjpeg).label == "MJPEG")
    }

    @Test func unsupportedIsToldFromAFailedStream() {
        #expect(KhalaLiveFailure.isUnsupported(message: "Camera does not support WebRTC, frontend_stream_types={hls}"))
        #expect(!KhalaLiveFailure.isUnsupported(message: "webrtc: streams: could not open"))
    }

    @Test func pageIsSelfContained() {
        let html = KhalaWebRTCPage.html(fit: .cover)
        #expect(html.contains("object-fit: cover"))
        #expect(!html.contains("{{FIT}}"))
        #expect(KhalaWebRTCPage.html(fit: .contain).contains("object-fit: contain"))
        // No remote anything, nothing to the console.
        #expect(!html.contains("src="))
        #expect(!html.contains("http"))
        #expect(!html.contains("console."))
        #expect(html.contains("playsinline muted autoplay"))
        #expect(html.contains("messageHandlers.\(KhalaWebRTCPage.messageHandler)"))
        #expect(html.contains("addTransceiver(\"audio\", { direction: \"recvonly\" })"))
        #expect(html.contains("addTransceiver(\"video\", { direction: \"recvonly\" })"))
    }
}

struct KhalaWebRTCSignalingTests {
    typealias Signaling = KhalaWebRTCSignaling
    private let config = KhalaWebRTCClientConfig.fallback(iceServers: ["stun:a"])
    private let local = KhalaIceCandidate(candidate: "candidate:1 1 udp 1 192.0.2.20 50000 typ host", sdpMid: "0")
    private let remote = KhalaIceCandidate(candidate: "candidate:2 1 udp 1 192.0.2.10 8555 typ host", sdpMLineIndex: 1)

    /// Up to the offer being out: page ready, server ready, config in, page offered.
    private func negotiating() -> (Signaling, [Signaling.Effect]) {
        var signaling = Signaling()
        var effects = signaling.handle(.page(.ready))
        effects += signaling.handle(.start)
        effects += signaling.handle(.serverReady(attempt: 1))
        effects += signaling.handle(.clientConfig(attempt: 1, config))
        effects += signaling.handle(.page(.offer(sdp: "v=0 offer")))
        return (signaling, effects)
    }

    private func playing() -> Signaling {
        var (signaling, _) = negotiating()
        _ = signaling.handle(.server(attempt: 1, .session(id: "S")))
        _ = signaling.handle(.server(attempt: 1, .answer(sdp: "v=0 answer")))
        _ = signaling.handle(.page(.frame(width: 640, height: 360)))
        return signaling
    }

    @Test func happyPathRunsTheFrontendsSequence() {
        var signaling = Signaling()
        #expect(signaling.handle(.start) == [
            .armServerWaitDeadline(attempt: 1, after: 20),
            .waitForServer(attempt: 1, freshConnection: false),
        ])
        #expect(signaling.handle(.serverReady(attempt: 1)) == [
            .cancelDeadlines, .armFirstFrameDeadline(attempt: 1, after: 6), .fetchClientConfig(attempt: 1),
        ])
        // Config before the page is ready: held until the page says ready.
        #expect(signaling.handle(.clientConfig(attempt: 1, config)) == [])
        #expect(signaling.handle(.page(.ready)) == [.page(.start(config))])
        #expect(signaling.handle(.page(.offer(sdp: "v=0 offer"))) == [.subscribeOffer(attempt: 1, sdp: "v=0 offer")])
        #expect(signaling.phase == .negotiating)
        // A local candidate before the session is buffered, then flushed with the session id.
        #expect(signaling.handle(.page(.candidate(local))) == [])
        #expect(signaling.handle(.server(attempt: 1, .session(id: "S"))) == [.sendCandidate(sessionId: "S", local)])
        #expect(signaling.handle(.page(.candidate(local))) == [.sendCandidate(sessionId: "S", local)])
        #expect(signaling.handle(.server(attempt: 1, .answer(sdp: "v=0 answer"))) == [.page(.answer(sdp: "v=0 answer"))])
        #expect(signaling.handle(.server(attempt: 1, .candidate(remote))) == [.page(.candidate(remote))])
        // The end-of-candidates marker goes on to the page, as the frontend adds it.
        #expect(signaling.handle(.server(attempt: 1, .candidate(nil))) == [.page(.endOfCandidates)])
        #expect(signaling.handle(.page(.frame(width: 2688, height: 1520))) == [.cancelDeadlines, .playing])
        #expect(signaling.handle(.page(.codec(mimeType: "video/H265"))) == [.codec("H.265")])
        #expect(signaling.phase == .playing)
    }

    @Test func configFetchFailureUsesTheDefaultsButNoWebRTCFallsBack() {
        var signaling = Signaling()
        _ = signaling.handle(.page(.ready))
        _ = signaling.handle(.start)
        _ = signaling.handle(.serverReady(attempt: 1))
        #expect(signaling.handle(.clientConfig(attempt: 1, nil))
            == [.page(.start(.fallback(iceServers: Signaling.fallbackICEServers)))])

        var unsupported = Signaling()
        _ = unsupported.handle(.start)
        _ = unsupported.handle(.serverReady(attempt: 1))
        #expect(unsupported.handle(.clientConfigUnsupported(attempt: 1)).last == .fallBack(.unsupported))
        #expect(unsupported.phase == .failed(.unsupported))
    }

    @Test func noFrameInTimeFallsBack() {
        var (signaling, _) = negotiating()
        _ = signaling.handle(.server(attempt: 1, .answer(sdp: "v=0 answer")))
        #expect(signaling.handle(.firstFrameDeadline(attempt: 1)) == [
            .cancelDeadlines, .unsubscribe, .page(.stop), .fallBack(.timeout),
        ])
        // Already failed: later events do nothing.
        #expect(signaling.handle(.page(.frame(width: 1, height: 1))) == [])
        #expect(signaling.handle(.firstFrameDeadline(attempt: 1)) == [])
    }

    @Test func iceFailureBeforeAFrameFallsBackAtOnce() {
        var (signaling, _) = negotiating()
        #expect(signaling.handle(.page(.ice(state: "checking"))) == [])
        #expect(signaling.handle(.page(.ice(state: "failed"))).last == .fallBack(.ice))
    }

    @Test func signalingErrorsAndPageErrorsFallBack() {
        var (rejected, _) = negotiating()
        #expect(rejected.handle(.offerRejected(attempt: 1, message: "Camera does not support WebRTC")).last
            == .fallBack(.unsupported))

        var (errored, _) = negotiating()
        #expect(errored.handle(.server(attempt: 1, .error(code: "webrtc_offer_failed", message: "no stream")))
            .last == .fallBack(.signaling("no stream")))

        var (threw, _) = negotiating()
        #expect(threw.handle(.page(.error(message: "script: x"))).last == .fallBack(.page("script: x")))
    }

    @Test func unreachableServerFallsBack() {
        var signaling = Signaling()
        _ = signaling.handle(.start)
        #expect(signaling.handle(.serverWaitDeadline(attempt: 1)).last == .fallBack(.noServer))

        var refused = Signaling()
        _ = refused.handle(.start)
        #expect(refused.handle(.serverUnusable(attempt: 1)).last == .fallBack(.noServer))
    }

    @Test func staleAttemptsAreIgnored() {
        var (signaling, _) = negotiating()
        _ = signaling.handle(.socketLost) // attempt 2 now waits for the server
        #expect(signaling.attempt == 2)
        #expect(signaling.handle(.server(attempt: 1, .answer(sdp: "old"))) == [])
        #expect(signaling.handle(.serverReady(attempt: 1)) == [])
        #expect(signaling.handle(.firstFrameDeadline(attempt: 1)) == [])
        #expect(signaling.handle(.clientConfig(attempt: 1, config)) == [])
        #expect(signaling.phase == .waitingForServer)
    }

    @Test func lostSocketRebuildsOnAFreshConnection() {
        var signaling = playing()
        #expect(signaling.handle(.socketLost) == [
            .cancelDeadlines, .unsubscribe, .page(.stop),
            .armServerWaitDeadline(attempt: 2, after: 20),
            .waitForServer(attempt: 2, freshConnection: true),
        ])
        #expect(signaling.sessionId == nil)
        // The page is still loaded, so the new attempt starts it straight after the config.
        _ = signaling.handle(.serverReady(attempt: 2))
        #expect(signaling.handle(.clientConfig(attempt: 2, config)) == [.page(.start(config))])
        // While waiting for the server a lost socket is the gate's business, not a second rebuild.
        var waiting = Signaling()
        _ = waiting.handle(.start)
        #expect(waiting.handle(.socketLost) == [])
    }

    @Test func playingStreamThatDropsIsGivenGraceThenRebuiltThenGivenUp() {
        var signaling = playing()
        #expect(signaling.handle(.page(.ice(state: "disconnected"))) == [.armRecoveryDeadline(attempt: 1, after: 4)])
        #expect(signaling.handle(.page(.ice(state: "connected"))) == [.cancelDeadlines])
        #expect(signaling.handle(.page(.ice(state: "disconnected"))) == [.armRecoveryDeadline(attempt: 1, after: 4)])
        let rebuilt = signaling.handle(.recoveryDeadline(attempt: 1))
        #expect(rebuilt.contains(.waitForServer(attempt: 2, freshConnection: false)))
        #expect(signaling.retries == 1)

        // Two rebuilds, then the third failure falls back.
        for n in 2 ... 3 {
            _ = signaling.handle(.serverReady(attempt: n))
            _ = signaling.handle(.clientConfig(attempt: n, config))
            _ = signaling.handle(.page(.offer(sdp: "v=0")))
            _ = signaling.handle(.page(.frame(width: 1, height: 1)))
            let effects = signaling.handle(.page(.ice(state: "failed")))
            if n == 2 {
                #expect(effects.contains(.waitForServer(attempt: 3, freshConnection: false)))
            } else {
                #expect(effects.last == .fallBack(.ice))
            }
        }
    }

    @Test func backgroundStopsAndForegroundStartsAgain() {
        var signaling = playing()
        #expect(signaling.handle(.backgrounded) == [.cancelDeadlines, .unsubscribe, .page(.stop)])
        #expect(signaling.phase == .suspended)
        #expect(signaling.handle(.backgrounded) == [])
        #expect(signaling.handle(.foregrounded) == [
            .armServerWaitDeadline(attempt: 2, after: 20), .waitForServer(attempt: 2, freshConnection: false),
        ])
        // Foregrounding a player that never backgrounded does nothing.
        var idle = Signaling()
        #expect(idle.handle(.foregrounded) == [])
    }

    @Test func stopTearsDownOnceAndSilencesEverything() {
        var signaling = playing()
        #expect(signaling.handle(.stop) == [.cancelDeadlines, .unsubscribe, .page(.stop)])
        #expect(signaling.handle(.stop) == [])
        #expect(signaling.handle(.page(.candidate(local))) == [])
        #expect(signaling.handle(.server(attempt: 1, .candidate(remote))) == [])
        #expect(signaling.handle(.page(.error(message: "late"))) == [])
        #expect(!signaling.isActive)
    }

    @Test func offerOnlyCountsWhileOffering() {
        var signaling = Signaling()
        _ = signaling.handle(.page(.ready))
        _ = signaling.handle(.start)
        #expect(signaling.handle(.page(.offer(sdp: "early"))) == [])
        #expect(signaling.phase == .waitingForServer)
    }
}
