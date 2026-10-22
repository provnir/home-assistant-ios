import Foundation
@testable import HomeAssistant
import Testing

/// Live player v2: the frontend's stream choice (`ha-camera-stream` `_streams`), the two-lane stage, the hidden
/// clean-up, the HLS master playlist (`ha-hls-player` `_startHls`), zoom math and the info sheet's stats.
struct KhalaStreamSelectionTests {
    private let video = KhalaStreamReport(hasAudio: false, hasVideo: true)
    private let videoAudio = KhalaStreamReport(hasAudio: true, hasVideo: true)
    private let both: [KhalaStreamKind] = [.hls, .webRTC]

    private func streams(
        _ supported: [KhalaStreamKind]?, hls: KhalaStreamReport? = nil, webRTC: KhalaStreamReport? = nil,
        muted: Bool = true
    ) -> [KhalaStreamSlot] {
        KhalaStreamSelection.streams(supported: supported, hls: hls, webRTC: webRTC, muted: muted)
    }

    @Test func capabilitiesDecideBeforeAnythingLoads() {
        #expect(streams(nil) == [])
        #expect(streams([]) == [KhalaStreamSlot(.mjpeg)])
        #expect(streams([.webRTC]) == [KhalaStreamSlot(.webRTC)])
        #expect(streams([.hls]) == [KhalaStreamSlot(.hls)])
        // Neither reported: both mount, HLS shown with the poster, WebRTC negotiating behind it.
        #expect(streams(both) == [KhalaStreamSlot(.hls), KhalaStreamSlot(.webRTC, visible: false)])
    }

    @Test func aSingleTypeThatFailsGivesWayToMJPEG() {
        #expect(streams([.webRTC], webRTC: .failed) == [KhalaStreamSlot(.mjpeg)])
        #expect(streams([.hls], hls: .failed) == [KhalaStreamSlot(.mjpeg)])
        #expect(streams([.webRTC], webRTC: video) == [KhalaStreamSlot(.webRTC)])
    }

    @Test func theFirstToReportDecidesWhatShowsWhileTheOtherLoads() {
        #expect(streams(both, hls: video) == [KhalaStreamSlot(.hls), KhalaStreamSlot(.webRTC, visible: false)])
        #expect(streams(both, hls: .failed) == [KhalaStreamSlot(.webRTC)])
        #expect(streams(both, webRTC: video) == [KhalaStreamSlot(.webRTC), KhalaStreamSlot(.hls, visible: false)])
        #expect(streams(both, webRTC: .failed) == [KhalaStreamSlot(.hls)])
    }

    @Test func fullyLoadedPrefersWebRTCUnlessOnlyHLSHasTheAudioWanted() {
        #expect(streams(both, hls: video, webRTC: video) == [KhalaStreamSlot(.webRTC)])
        #expect(streams(both, hls: videoAudio, webRTC: video, muted: true) == [KhalaStreamSlot(.webRTC)])
        #expect(streams(both, hls: videoAudio, webRTC: video, muted: false) == [KhalaStreamSlot(.hls)])
        #expect(streams(both, hls: videoAudio, webRTC: videoAudio, muted: false) == [KhalaStreamSlot(.webRTC)])
        #expect(streams(both, hls: .failed, webRTC: .failed) == [KhalaStreamSlot(.mjpeg)])
        // Khala's one change: WebRTC out, HLS with video → HLS (the frontend would fall to MJPEG).
        #expect(streams(both, hls: video, webRTC: .failed) == [KhalaStreamSlot(.hls)])
    }
}

struct KhalaLiveStageTests {
    private let video = KhalaStreamReport(hasAudio: false, hasVideo: true)

    @Test func raceShowsHLSFirstThenWebRTCWinsAndHLSStops() {
        var stage = KhalaLiveStage(supported: [.hls, .webRTC], muted: true)
        #expect(stage.start() == [.startLane(.hls), .startLane(.webRTC), .show(.hls)])
        #expect(stage.isLoading)
        // HLS's playlist parses first: nothing changes, HLS stays on screen.
        #expect(stage.report(.hls, video) == [])
        // WebRTC's first frame: it comes to the front and HLS is let go.
        #expect(stage.report(.webRTC, video) == [.stopLane(.hls), .show(.webRTC)])
        #expect(stage.setPlaying(.webRTC, true) == [])
        #expect(!stage.isLoading)
        #expect(stage.running == [.webRTC])
    }

    @Test func webRTCWinningBeforeHLSReportsKeepsHLSLoadingUnderneathUntilItDoes() {
        var stage = KhalaLiveStage(supported: [.hls, .webRTC], muted: true)
        _ = stage.start()
        #expect(stage.report(.webRTC, video) == [.show(.webRTC)])
        #expect(stage.running == [.hls, .webRTC])
        #expect(stage.report(.hls, video) == [.stopLane(.hls)])
    }

    @Test func aWebRTCFailureSwitchesToHLSInPlace() {
        var stage = KhalaLiveStage(supported: [.hls, .webRTC], muted: true)
        _ = stage.start()
        _ = stage.report(.hls, video)
        _ = stage.setPlaying(.hls, true)
        #expect(!stage.isLoading)
        #expect(stage.report(.webRTC, .failed) == [.stopLane(.webRTC)])
        #expect(stage.front == .hls)
        #expect(!stage.isLoading)
    }

    @Test func aWebRTCFailureAfterItWonBringsHLSBack() {
        var stage = KhalaLiveStage(supported: [.hls, .webRTC], muted: true)
        _ = stage.start()
        _ = stage.report(.hls, video)
        _ = stage.report(.webRTC, video)
        _ = stage.setPlaying(.webRTC, true)
        #expect(stage.report(.webRTC, .failed) == [.stopLane(.webRTC), .startLane(.hls), .show(.hls)])
        #expect(stage.isLoading)
    }

    @Test func bothFailingGivesUpOnceWithEverythingStopped() {
        var stage = KhalaLiveStage(supported: [.hls, .webRTC], muted: true)
        _ = stage.start()
        #expect(stage.report(.hls, .failed) == [.stopLane(.hls), .show(.webRTC)])
        #expect(stage.report(.webRTC, .failed) == [.stopLane(.webRTC), .giveUp])
        #expect(stage.hasGivenUp)
        #expect(stage.isLoading)
        #expect(stage.report(.webRTC, .failed) == [])
    }

    @Test func aWebRTCOnlyCameraGivesUpWhenWebRTCFails() {
        var stage = KhalaLiveStage(supported: [.webRTC], muted: true)
        #expect(stage.start() == [.startLane(.webRTC), .show(.webRTC)])
        #expect(stage.report(.webRTC, .failed) == [.stopLane(.webRTC), .giveUp])
    }

    @Test func unmutingForAudioOnlyHLSHasSwitchesAndMutingSwitchesBack() {
        var stage = KhalaLiveStage(supported: [.hls, .webRTC], muted: true)
        _ = stage.start()
        _ = stage.report(.hls, KhalaStreamReport(hasAudio: true, hasVideo: true))
        _ = stage.report(.webRTC, video)
        #expect(stage.front == .webRTC)
        #expect(stage.setMuted(false) == [.stopLane(.webRTC), .startLane(.hls), .show(.hls)])
        #expect(stage.setMuted(true) == [.stopLane(.hls), .startLane(.webRTC), .show(.webRTC)])
    }

    @Test func reportsFromLanesNotRunningAreIgnoredAndStopThenStartIsAFreshRace() {
        var stage = KhalaLiveStage(supported: [.hls, .webRTC], muted: true)
        #expect(stage.report(.webRTC, video) == [])
        _ = stage.start()
        #expect(stage.stop() == [.stopLane(.hls), .stopLane(.webRTC)])
        #expect(stage.report(.webRTC, video) == [])
        #expect(stage.setPlaying(.hls, true) == [])
        #expect(stage.start() == [.startLane(.hls), .startLane(.webRTC), .show(.hls)])
        #expect(stage.hls == nil && stage.webRTC == nil)
    }
}

struct KhalaLiveVisibilityTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func aShortTripAwayKeepsTheStream() {
        var visibility = KhalaLiveVisibility()
        #expect(visibility.backgrounded(at: start, isPlaying: true) == .armCleanup(token: 1, after: 60))
        #expect(visibility.foregrounded(at: start.addingTimeInterval(10)) == .keep)
        // The timer from that trip is spent.
        #expect(visibility.cleanupDeadline(token: 1) == .keep)
    }

    @Test func sixtySecondsAwayCleansUpAndReturnResumes() {
        var visibility = KhalaLiveVisibility()
        _ = visibility.backgrounded(at: start, isPlaying: true)
        #expect(visibility.cleanupDeadline(token: 1) == .cleanUp)
        #expect(visibility.cleanupDeadline(token: 1) == .keep)
        #expect(visibility.foregrounded(at: start.addingTimeInterval(90)) == .resume)
    }

    @Test func aSuspendedAppThatMissedItsTimerRestartsOnReturn() {
        var visibility = KhalaLiveVisibility()
        _ = visibility.backgrounded(at: start, isPlaying: true)
        #expect(visibility.foregrounded(at: start.addingTimeInterval(61)) == .restart)
    }

    @Test func aStreamNotYetPlayingIsCleanedUpAtOnce() {
        var visibility = KhalaLiveVisibility()
        #expect(visibility.backgrounded(at: start, isPlaying: false) == .cleanUp)
        #expect(visibility.backgrounded(at: start, isPlaying: false) == .keep)
        #expect(visibility.foregrounded(at: start.addingTimeInterval(1)) == .resume)
    }

    @Test func pictureInPictureKeepsTheStreamUntilItEndsInTheBackground() {
        var visibility = KhalaLiveVisibility()
        #expect(visibility.pictureInPicture(true, inBackground: false, at: start, isPlaying: true) == .keep)
        #expect(visibility.backgrounded(at: start, isPlaying: true) == .keep)
        #expect(visibility.pictureInPicture(false, inBackground: true, at: start, isPlaying: true)
            == .armCleanup(token: 1, after: 60))
    }

    @Test func aLostSocketWhileHiddenCleansUp() {
        var visibility = KhalaLiveVisibility()
        #expect(visibility.socketLost() == .keep)
        _ = visibility.backgrounded(at: start, isPlaying: true)
        #expect(visibility.socketLost() == .cleanUp)
        #expect(visibility.isHidden)
        #expect(visibility.foregrounded(at: start.addingTimeInterval(2)) == .resume)
        #expect(!visibility.isHidden)
    }

    @Test func aTimerFromAnEarlierTripCannotCleanUpALaterOne() {
        var visibility = KhalaLiveVisibility()
        _ = visibility.backgrounded(at: start, isPlaying: true)
        _ = visibility.foregrounded(at: start.addingTimeInterval(5))
        #expect(visibility.backgrounded(at: start.addingTimeInterval(6), isPlaying: true)
            == .armCleanup(token: 3, after: 60))
        #expect(visibility.cleanupDeadline(token: 1) == .keep)
        #expect(visibility.cleanupDeadline(token: 3) == .cleanUp)
    }
}

struct KhalaHLSPlaylistTests {
    private let master = URL(string: "https://ha.example.org/api/hls/TOKEN/master_playlist.m3u8")!

    @Test func homeAssistantsVideoOnlyMasterPlaysItsMediaPlaylist() {
        let text = "#EXTM3U\n#EXT-X-VERSION:6\n#EXT-X-INDEPENDENT-SEGMENTS\n"
            + "#EXT-X-STREAM-INF:BANDWIDTH=6144000,CODECS=\"hvc1.1.6.L153.B0\"\nplaylist.m3u8\n"
        let playlist = KhalaHLSPlaylist(master: text, url: master)
        #expect(playlist.playlistURL.absoluteString == "https://ha.example.org/api/hls/TOKEN/playlist.m3u8")
        // One CODECS entry: the frontend's pattern finds no pair ("undefined,undefined"): video, no audio.
        #expect(playlist.codecs == ["undefined", "undefined"])
        #expect(playlist.report == KhalaStreamReport(hasAudio: false, hasVideo: true))
        #expect(playlist.videoCodec == "H.265")
    }

    @Test func videoAndAudioAreReadFromTheCodecPair() {
        let text = "#EXTM3U\r\n#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS=\"avc1.640028,mp4a.40.2\"\r\n/api/hls/T/playlist.m3u8\r\n"
        let playlist = KhalaHLSPlaylist(master: text, url: master)
        #expect(playlist.codecs == ["avc1", "mp4a"])
        #expect(playlist.report == KhalaStreamReport(hasAudio: true, hasVideo: true))
        #expect(playlist.playlistURL.absoluteString == "https://ha.example.org/api/hls/T/playlist.m3u8")
        #expect(playlist.videoCodec == "H.264")
    }

    @Test func moreThanOneVariantOrNoneKeepsTheMaster() {
        let two = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\na.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=2\nb.m3u8\n"
        #expect(KhalaHLSPlaylist(master: two, url: master).playlistURL == master)
        let none = KhalaHLSPlaylist(master: "#EXTM3U\n", url: master)
        #expect(none.playlistURL == master)
        #expect(none.codecs == nil)
        #expect(none.report == .failed)
    }
}

struct KhalaLiveZoomTests {
    @Test func doubleTapWalksTheSteps() {
        #expect(KhalaLiveZoom.nextStep(after: 1) == 2.5)
        #expect(KhalaLiveZoom.nextStep(after: 2.5) == 4)
        #expect(KhalaLiveZoom.nextStep(after: 4) == 1)
        #expect(KhalaLiveZoom.nextStep(after: 3) == 4)
        #expect(KhalaLiveZoom.nextStep(after: 4.3) == 1)
        #expect(KhalaLiveZoom.nextStep(after: 1.8) == 2.5)
    }

    @Test func theZoomRectangleCentresOnTheTapButStaysInside() {
        let size = CGSize(width: 400, height: 225)
        #expect(KhalaLiveZoom.zoomRect(scale: 2, center: CGPoint(x: 200, y: 112.5), in: size)
            == CGRect(x: 100, y: 56.25, width: 200, height: 112.5))
        // A tap in the corner zooms into the corner, not past it.
        #expect(KhalaLiveZoom.zoomRect(scale: 4, center: CGPoint(x: 0, y: 0), in: size)
            == CGRect(x: 0, y: 0, width: 100, height: 56.25))
        #expect(KhalaLiveZoom.zoomRect(scale: 4, center: CGPoint(x: 400, y: 225), in: size)
            == CGRect(x: 300, y: 168.75, width: 100, height: 56.25))
        // Out-of-range scales are held to the limits.
        #expect(KhalaLiveZoom.zoomRect(scale: 10, center: CGPoint(x: 200, y: 100), in: size).width == 100)
        #expect(KhalaLiveZoom.zoomRect(scale: 0.5, center: CGPoint(x: 200, y: 100), in: size).width == 400)
    }

    @Test func chipLabelsAndSwipeDown() {
        #expect(KhalaLiveZoom.label(1) == nil)
        #expect(KhalaLiveZoom.label(1.01) == nil)
        #expect(KhalaLiveZoom.label(2.5) == "2.5×")
        #expect(KhalaLiveZoom.label(4) == "4×")
        #expect(KhalaLiveZoom.label(1.83) == "1.8×")
        #expect(KhalaLiveZoom.shouldDismiss(translation: 120, velocity: 0))
        #expect(KhalaLiveZoom.shouldDismiss(translation: 30, velocity: 1200))
        #expect(!KhalaLiveZoom.shouldDismiss(translation: 60, velocity: 300))
        #expect(KhalaLiveZoom.dismissProgress(translation: 200, height: 800) == 0.5)
        #expect(KhalaLiveZoom.dismissProgress(translation: 2000, height: 800) == 1)
        #expect(KhalaLiveZoom.dismissProgress(translation: 10, height: 0) == 0)
    }
}

struct KhalaLiveStatsTests {
    private func webRTC(_ t: Double, bytes: Double, frames: Double, fps: Any? = nil) -> KhalaLiveStats.Sample? {
        var json: [String: Any] = [
            "lane": "webrtc", "t": t, "bytes": bytes, "frames": frames, "w": 2688, "h": 1520.0,
            "dropped": 3, "lost": 12, "jitter": 0.004, "codec": "video/H265", "rtt": 0.012,
            "local": "host", "remote": "host", "protocol": "udp",
        ]
        if let fps { json["fps"] = fps }
        return KhalaLiveStats.Sample(json: json)
    }

    @Test func ratesComeFromTwoSamples() throws {
        let first = try #require(webRTC(10000, bytes: 1_000_000, frames: 100))
        let second = try #require(webRTC(11000, bytes: 1_750_000, frames: 125))
        let alone = KhalaLiveStats(first, previous: nil)
        #expect(alone.bitrate == nil)
        #expect(alone.framesPerSecond == nil)
        let stats = KhalaLiveStats(second, previous: first)
        #expect(stats.bitrate == 6000)
        #expect(stats.framesPerSecond == 25)
        #expect(stats.codec == "H.265")
        #expect(stats.resolution == "2688×1520")
        #expect(stats.roundTripTime == 12)
        #expect(stats.route == "Direct · UDP")
        #expect(stats.rows.map { $0.title } == [
            "Path", "Codec", "Resolution", "Frame rate", "Bitrate", "Round trip", "Route", "Jitter",
            "Packets lost", "Frames dropped",
        ])
        #expect(stats.rows.first { $0.title == "Bitrate" }?.value == "6.0 Mbps")
        #expect(stats.rows.first { $0.title == "Frame rate" }?.value == "25 fps")
    }

    @Test func theStreamsOwnFrameRateWinsAndBadNumbersAreDropped() throws {
        let first = try #require(webRTC(10000, bytes: 0, frames: 0))
        let reported = try #require(webRTC(11000, bytes: 100, frames: 10, fps: 24.0))
        #expect(KhalaLiveStats(reported, previous: first).framesPerSecond == 24)
        let broken = try #require(KhalaLiveStats.Sample(json: ["lane": "webrtc", "t": 1.0, "bytes": Double.nan]))
        #expect(broken.bytes == nil)
        #expect(KhalaLiveStats.Sample(json: ["lane": "other", "t": 1.0]) == nil)
        #expect(KhalaLiveStats.Sample(json: ["lane": "hls"]) == nil)
        // A previous sample from the other lane, or out of order, gives no rates.
        let hls = try #require(KhalaLiveStats.Sample(json: ["lane": "hls", "t": 9000.0, "bytes": 0]))
        #expect(KhalaLiveStats(reported, previous: hls).bitrate == nil)
        #expect(KhalaLiveStats(first, previous: reported).bitrate == nil)
    }

    @Test func hlsShowsHowFarBehindLiveItIs() throws {
        let sample = try #require(KhalaLiveStats.Sample(json: [
            "lane": "hls", "t": 5000.0, "w": 2688, "h": 1520, "behind": 6.24, "frames": 10, "dropped": 0,
        ]))
        let stats = KhalaLiveStats(sample, previous: nil, codec: "H.265")
        #expect(stats.transport == "HLS")
        #expect(stats.codec == "H.265")
        #expect(stats.rows.first { $0.title == "Behind live" }?.value == "6.2 s")
    }

    @Test func routesAndBitrates() {
        #expect(KhalaLiveStats.route(local: "relay", remote: "host", transport: "udp") == "Relay (TURN) · UDP")
        #expect(KhalaLiveStats.route(local: "srflx", remote: "host", transport: nil) == "Via STUN")
        #expect(KhalaLiveStats.route(local: nil, remote: nil, transport: "udp") == nil)
        #expect(KhalaLiveStats.bitrateText(850) == "850 kbps")
        #expect(KhalaLiveStats.bitrateText(5800) == "5.8 Mbps")
    }
}

struct KhalaLivePageV2Tests {
    @Test func thePageCarriesBothLanesTheFrontendWay() {
        let html = KhalaWebRTCPage.html(fit: .contain)
        #expect(html.contains("Ported from the Home Assistant frontend (Apache-2.0), release 20260930.4"))
        #expect(html.contains("<video id=\"rtc\""))
        #expect(html.contains("<video id=\"hls\""))
        // Picture in picture is allowed now.
        #expect(!html.contains("disablepictureinpicture"))
        #expect(html.contains("webkitSetPresentationMode"))
        // `_addTrack`: audio held back from the stream while muted, added on unmute.
        #expect(html.contains("if (muted) { heldAudio.push(event.track); return; }"))
        #expect(html.contains("heldAudio.forEach(function (track) { stream.addTrack(track); });"))
        // End of candidates as the frontend passes it.
        #expect(html.contains("pc.addIceCandidate({ candidate: \"\", sdpMid: \"0\" })"))
        // `_renderHLSNative`: play() once the metadata is in.
        #expect(html.contains("hlsVideo.onloadedmetadata"))
        // Stats send candidate types, never an address.
        #expect(!html.contains(".address"))
        #expect(!html.contains(".ip"))
    }

    @Test func newMessagesAndCommands() {
        #expect(KhalaWebRTCPageMessage(body: ["type": "audio"]) == .audio)
        #expect(KhalaWebRTCPageMessage(body: ["type": "poster"]) == .poster)
        #expect(KhalaWebRTCPageMessage(body: ["type": "presentation", "mode": "picture-in-picture"])
            == .presentation(mode: "picture-in-picture"))
        #expect(KhalaWebRTCPageMessage(body: ["type": "hls", "event": "frame", "width": 2688, "height": 1520])
            == .hls(.frame(width: 2688, height: 1520)))
        #expect(KhalaWebRTCPageMessage(body: ["type": "hls", "event": "error", "message": "media error 2"])
            == .hls(.error(message: "media error 2")))
        #expect(KhalaWebRTCPageMessage(body: ["type": "hls", "event": "nope"]) == nil)

        let url = "https://ha.example.org/api/hls/T/playlist.m3u8?x=\"');"
        let start = KhalaWebRTCPageCommand.hlsStart(url: url).javaScript
        let argument = String(start.dropFirst("window.khala.hlsStart(".count).dropLast(2))
        let decoded = try? JSONSerialization.jsonObject(with: Data("[\(argument)]".utf8)) as? [String]
        #expect(decoded == [url])
        #expect(KhalaWebRTCPageCommand.show(.hls).javaScript == "window.khala.show(\"hls\");")
        #expect(KhalaWebRTCPageCommand.show(.webRTC).javaScript == "window.khala.show(\"rtc\");")
        #expect(KhalaWebRTCPageCommand.endOfCandidates.javaScript == "window.khala.endOfCandidates();")
        #expect(!KhalaWebRTCPageCommand.hlsStart(url: url).isEssential)
        #expect(!KhalaWebRTCPageCommand.togglePictureInPicture.isEssential)
    }

    @Test func pageMessagesForTheSessionLeaveTheWebRTCLaneAlone() {
        var signaling = KhalaWebRTCSignaling()
        _ = signaling.handle(.page(.ready))
        _ = signaling.handle(.start)
        for message: KhalaWebRTCPageMessage in [.audio, .poster, .presentation(mode: "inline"), .hls(.error(message: "x"))] {
            #expect(signaling.handle(.page(message)) == [])
        }
        #expect(signaling.phase == .waitingForServer)
    }

    @Test func lanesFollowTheEngineAndTheMemory() {
        let plan = ["webrtc", "hls", "mjpeg"]
        func lanes(_ engine: KhalaLiveEngine, _ players: [String], failed: Bool) -> KhalaLiveLanes {
            engine.lanes(players, webRTC: "webrtc", hls: "hls", webKitFailedRepeatedly: failed)
        }
        #expect(lanes(.auto, plan, failed: false) == KhalaLiveLanes(webRTC: true, hls: true))
        #expect(lanes(.auto, plan, failed: true) == KhalaLiveLanes(webRTC: false, hls: true))
        #expect(lanes(.webKit, plan, failed: true) == KhalaLiveLanes(webRTC: true, hls: true))
        #expect(lanes(.auto, ["webrtc", "mjpeg"], failed: false) == KhalaLiveLanes(webRTC: true, hls: false))
        #expect(KhalaLiveLanes(webRTC: true, hls: true).streamKinds == [.hls, .webRTC])
        #expect(KhalaLivePath(.hls, codec: "H.265").label == "HLS · H.265")
    }
}
