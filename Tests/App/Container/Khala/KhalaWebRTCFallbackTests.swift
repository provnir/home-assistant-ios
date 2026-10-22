import Foundation
@testable import HomeAssistant
import Testing

/// Build 30.1 on device: "for a second it said WebRTC, then HLS, then the app crashed". These pin the fixes: the
/// page no longer gives way on an interrupted play(), the signaling gives way exactly once and goes quiet after a
/// stop, and the fallback memory / engine setting route a camera that keeps failing straight to HLS.
struct KhalaWebRTCFallbackTests {
    typealias Signaling = KhalaWebRTCSignaling
    private let config = KhalaWebRTCClientConfig.fallback(iceServers: ["stun:a"])
    private let local = KhalaIceCandidate(candidate: "candidate:1 1 udp 1 192.0.2.20 50000 typ host", sdpMid: "0")
    private let remote = KhalaIceCandidate(candidate: "candidate:2 1 udp 1 192.0.2.10 8555 typ host", sdpMLineIndex: 1)

    private func negotiating() -> Signaling {
        var signaling = Signaling()
        _ = signaling.handle(.page(.ready))
        _ = signaling.handle(.start)
        _ = signaling.handle(.serverReady(attempt: 1))
        _ = signaling.handle(.clientConfig(attempt: 1, config))
        _ = signaling.handle(.page(.offer(sdp: "v=0 offer")))
        _ = signaling.handle(.server(attempt: 1, .session(id: "S")))
        _ = signaling.handle(.server(attempt: 1, .answer(sdp: "v=0 answer")))
        return signaling
    }

    /// Every event the session can feed in, for "nothing happens any more" checks.
    private var everyEvent: [Signaling.Event] {
        [
            .start, .stop, .backgrounded, .foregrounded,
            .serverReady(attempt: 1), .serverUnusable(attempt: 1),
            .clientConfig(attempt: 1, config), .clientConfigUnsupported(attempt: 1),
            .offerRejected(attempt: 1, message: "x"),
            .server(attempt: 1, .session(id: "S2")), .server(attempt: 1, .answer(sdp: "v=0")),
            .server(attempt: 1, .candidate(remote)), .server(attempt: 1, .error(code: "e", message: "m")),
            .page(.ready), .page(.offer(sdp: "v=0")), .page(.candidate(local)), .page(.ice(state: "failed")),
            .page(.ice(state: "disconnected")), .page(.frame(width: 1, height: 1)),
            .page(.codec(mimeType: "video/H265")), .page(.error(message: "late")), .page(.note(message: "late")),
            .socketLost, .serverWaitDeadline(attempt: 1), .firstFrameDeadline(attempt: 1), .recoveryDeadline(attempt: 1),
        ]
    }

    // MARK: Page

    @Test func pageAttachesTheStreamOnceAndNeverGivesWayOnPlayOrStats() {
        let html = KhalaWebRTCPage.html(fit: .cover)
        // Exactly one `srcObject = stream`, in start(), not per track event (the AbortError of 30.1).
        #expect(html.components(separatedBy: "video.srcObject = stream;").count == 2)
        let ontrack = html.components(separatedBy: "pc.ontrack = function").last ?? ""
        let ontrackBody = ontrack.components(separatedBy: "pc.addTransceiver").first ?? ""
        #expect(!ontrackBody.contains("srcObject"))
        #expect(ontrackBody.contains("note(\"play\""))
        #expect(!ontrackBody.contains("fail(\"play\""))
        #expect(html.contains("note(\"stats\""))
        #expect(!html.contains("fail(\"stats\""))
        // First frame from any of: media events, the clock, a frame callback, decoded-frame stats.
        #expect(html.contains("requestVideoFrameCallback"))
        #expect(html.contains("framesDecoded > 0"))
        #expect(html.contains("video.currentTime"))
        // Every page call returns a value WebKit can bridge.
        #expect(html.contains("stop: function () {\n      cleanUp();\n      return true;"))
    }

    @Test func noteDecodesAndIsNeverFatal() {
        #expect(KhalaWebRTCPageMessage(body: ["type": "note", "message": "play: AbortError: x"])
            == .note(message: "play: AbortError: x"))
        var signaling = negotiating()
        #expect(signaling.handle(.page(.note(message: "play: AbortError"))) == [])
        #expect(signaling.phase == .negotiating)
    }

    @Test func onlyStartAndAnswerFailuresAreEssential() {
        #expect(KhalaWebRTCPageCommand.start(config).isEssential)
        #expect(KhalaWebRTCPageCommand.answer(sdp: "v=0").isEssential)
        #expect(!KhalaWebRTCPageCommand.candidate(remote).isEssential)
        #expect(!KhalaWebRTCPageCommand.setMuted(true).isEssential)
        #expect(!KhalaWebRTCPageCommand.stop.isEssential)
    }

    // MARK: Fallback triggers

    @Test func onlyFailedICEIsFatalBeforeTheFirstFrame() {
        for state in ["new", "checking", "disconnected", "closed", "connected", "completed"] {
            var signaling = negotiating()
            #expect(signaling.handle(.page(.ice(state: state))) == [], "ICE \(state) before a frame")
            #expect(signaling.phase == .negotiating)
        }
        var failed = negotiating()
        #expect(failed.handle(.page(.ice(state: "failed"))).last == .fallBack(.ice))
    }

    @Test func eachTriggerGivesWayOnceWithTheTeardownFirst() {
        let triggers: [(Signaling.Event, KhalaLiveFailure)] = [
            (.page(.error(message: "offer: x")), .page("offer: x")),
            (.page(.ice(state: "failed")), .ice),
            (.firstFrameDeadline(attempt: 1), .timeout),
            (.server(attempt: 1, .error(code: "webrtc_offer_failed", message: "no stream")), .signaling("no stream")),
        ]
        for (trigger, failure) in triggers {
            var signaling = negotiating()
            #expect(signaling.handle(trigger) == [.cancelDeadlines, .unsubscribe, .page(.stop), .fallBack(failure)])
            #expect(signaling.phase == .failed(failure))
            // A second trigger of any kind: no second teardown, no second fallback.
            for event in everyEvent where event != .start {
                #expect(!signaling.handle(event).contains(where: {
                    if case .fallBack = $0 { return true }
                    return $0 == .unsubscribe || $0 == .page(.stop)
                }), "after \(failure): \(event)")
            }
        }
    }

    @Test func stopAfterGivingWayClosesNothingTwice() {
        var signaling = negotiating()
        _ = signaling.handle(.page(.error(message: "x")))
        #expect(signaling.handle(.stop) == [])
        #expect(signaling.phase == .stopped)
    }

    // MARK: After stop

    @Test func everyEventAfterStopIsIgnored() {
        var signaling = negotiating()
        #expect(signaling.handle(.stop) == [.cancelDeadlines, .unsubscribe, .page(.stop)])
        for event in everyEvent where event != .start {
            #expect(signaling.handle(event) == [], "after stop: \(event)")
            #expect(signaling.phase == .stopped)
        }
        #expect(!signaling.isActive)
    }

    @Test func stopBeforeStartAndStopWhileSuspendedDoNothing() {
        var idle = Signaling()
        #expect(idle.handle(.stop) == [])
        var suspended = negotiating()
        _ = suspended.handle(.backgrounded)
        #expect(suspended.handle(.stop) == [])
        #expect(suspended.handle(.foregrounded) == [])
    }

    // MARK: No double transitions

    @Test func aSecondFrameOrPlayingSignalChangesNothing() {
        var signaling = negotiating()
        #expect(signaling.handle(.page(.frame(width: 640, height: 360))) == [.cancelDeadlines, .playing])
        #expect(signaling.handle(.page(.frame(width: 640, height: 360))) == [])
        #expect(signaling.handle(.firstFrameDeadline(attempt: 1)) == [])
        #expect(signaling.phase == .playing)
    }

    @Test func aLateDeadlineOrStaleServerEventCannotFailANewAttempt() {
        var signaling = negotiating()
        _ = signaling.handle(.socketLost) // attempt 2
        #expect(signaling.handle(.firstFrameDeadline(attempt: 1)) == [])
        #expect(signaling.handle(.server(attempt: 1, .error(code: "e", message: "old"))) == [])
        #expect(signaling.handle(.offerRejected(attempt: 1, message: "old")) == [])
        #expect(signaling.phase == .waitingForServer)
    }

    // MARK: Engine + memory

    @Test func autoSkipsWebKitOnlyAfterTwoCountedFailuresOnThatCamera() {
        var memory = KhalaLiveFallbackMemory()
        memory.record(.unsupported, cameraEntityId: "camera.a")
        memory.record(.noServer, cameraEntityId: "camera.a")
        #expect(!memory.skipsWebKit(cameraEntityId: "camera.a"))
        memory.record(.page("play: AbortError"), cameraEntityId: "camera.a")
        #expect(!memory.skipsWebKit(cameraEntityId: "camera.a"))
        memory.record(.timeout, cameraEntityId: "camera.a")
        #expect(memory.skipsWebKit(cameraEntityId: "camera.a"))
        #expect(!memory.skipsWebKit(cameraEntityId: "camera.b"))
        #expect(memory.lastFallback == "camera.a: no frame in time")
        memory.reset()
        #expect(!memory.skipsWebKit(cameraEntityId: "camera.a"))
        #expect(memory.lastFallback == nil)
    }

    @Test func enginePlans() {
        let plan = ["webrtc", "hls", "mjpeg"]
        func planned(_ engine: KhalaLiveEngine, _ players: [String], failed: Bool) -> [String] {
            engine.plan(players, webRTC: "webrtc", hls: "hls", webKitFailedRepeatedly: failed)
        }
        #expect(planned(.auto, plan, failed: false) == plan)
        // With HLS on offer, repeated WebRTC failures keep the WebKit page (on its HLS lane, see lanes).
        #expect(planned(.auto, plan, failed: true) == plan)
        // A camera without HLS has nothing left for the page: on to MJPEG.
        #expect(planned(.auto, ["webrtc", "mjpeg"], failed: true) == ["mjpeg"])
        #expect(planned(.webKit, plan, failed: true) == plan)
        #expect(planned(.hls, plan, failed: false) == ["hls", "mjpeg"])
        // A WebRTC-only camera keeps WebRTC rather than nothing.
        #expect(planned(.hls, ["webrtc"], failed: false) == ["webrtc"])
        #expect(KhalaLiveEngine(stored: "hls") == .hls)
        #expect(KhalaLiveEngine(stored: "bogus") == .auto)
        #expect(KhalaLiveEngine(stored: nil) == .auto)
    }

    // MARK: Logging and parsing safety

    @Test func reasonsAreLoggedWithoutURLs() {
        let failure = KhalaLiveFailure.signaling("ffmpeg: rtsp://admin:secret@192.0.2.5:554/Streaming 404 not found")
        #expect(failure.logDescription == "signaling error: ffmpeg: <url> 404 not found")
        #expect(!failure.logDescription.contains("secret"))
        #expect(KhalaLiveFailure.page("play: AbortError: The operation was aborted.").logDescription
            == "page error: play: AbortError: The operation was aborted.")
        #expect(KhalaLiveFailure.redacted(String(repeating: "x", count: 500)).count == 160)
        #expect(!KhalaLiveFailure.unsupported.countsAgainstWebKit)
        #expect(KhalaLiveFailure.ice.countsAgainstWebKit)
    }

    @Test func nonFiniteNumbersFromThePageNeverTrap() {
        #expect(KhalaJSON.int(Double.nan) == nil)
        #expect(KhalaJSON.int(Double.infinity) == nil)
        #expect(KhalaJSON.int(1e300) == nil)
        #expect(KhalaJSON.int(1520.0) == 1520)
        #expect(KhalaWebRTCPageMessage(body: ["type": "frame", "width": Double.nan, "height": 1.0])
            == .frame(width: 0, height: 1))
    }
}
