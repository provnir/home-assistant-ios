import Foundation

// The live player's stream choice, ported from the Home Assistant frontend (Apache-2.0), release 20260930.4 (the
// frontend HA 2026.10.x serves):
// - `src/components/ha-camera-stream.ts` `_streams`: which of HLS and WebRTC to mount, and which one shows;
// - `src/components/ha-hls-player.ts` `_startHls` / `_reportStreams`: the master playlist's media playlist and codecs;
// - `src/components/ha-web-rtc-player.ts` / `ha-hls-player.ts` `_handleVisibilityChange`: 60 s before a hidden
//   stream is cleaned up.
// Foundation only, so the rules run on Linux (`Tools/Khala/linux-check.sh`).

/// The frontend's stream types (`data/camera.ts` `STREAM_TYPE_HLS`, `STREAM_TYPE_WEB_RTC`) and its last resort,
/// the MJPEG proxy.
enum KhalaStreamKind: String, Equatable, CaseIterable {
    case hls
    case webRTC = "web_rtc"
    case mjpeg
}

/// The frontend's `streams` event: what a player found in its stream.
struct KhalaStreamReport: Equatable {
    var hasAudio: Bool
    var hasVideo: Bool

    /// What a player reports when it cannot play at all.
    static let failed = KhalaStreamReport(hasAudio: false, hasVideo: false)
}

/// One mounted player and whether it is the one on screen.
struct KhalaStreamSlot: Equatable {
    let kind: KhalaStreamKind
    let visible: Bool

    init(_ kind: KhalaStreamKind, visible: Bool = true) {
        self.kind = kind
        self.visible = visible
    }
}

enum KhalaStreamSelection {
    /// `ha-camera-stream` `_streams`, line for line, with one deliberate change: once both players have reported
    /// and WebRTC has no video while HLS does, HLS plays. The frontend falls to MJPEG there ("both streams failed
    /// to load"), which is only right when HLS failed too; its WebRTC player never reports `hasVideo: false` except
    /// in a browser without WebRTC, so it never meets the case, but ours does when WebRTC gives up.
    ///
    /// - Parameters:
    ///   - supported: `camera/capabilities` `frontend_stream_types`; `nil` while they are not known.
    ///   - hls / webRTC: each player's last report, `nil` while it has not reported.
    ///   - muted: whether the player is muted (HLS wins only for audio WebRTC lacks, and only when heard).
    static func streams(
        supported: [KhalaStreamKind]?,
        hls: KhalaStreamReport?,
        webRTC: KhalaStreamReport?,
        muted: Bool
    ) -> [KhalaStreamSlot] {
        guard let supported else { return [] }
        let types = supported.filter { $0 != .mjpeg }
        if types.isEmpty {
            // Doesn't support any stream type: the MJPEG proxy.
            return [KhalaStreamSlot(.mjpeg)]
        }
        if types.count == 1 {
            // Only one stream type, no need to choose; a failed one gives way to MJPEG.
            let only = types[0]
            if (only == .hls && hls?.hasVideo == false) || (only == .webRTC && webRTC?.hasVideo == false) {
                return [KhalaStreamSlot(.mjpeg)]
            }
            return [KhalaStreamSlot(only)]
        }
        if let hls, let webRTC {
            // Fully loaded.
            if hls.hasVideo, hls.hasAudio, !webRTC.hasAudio, !muted {
                // WebRTC is missing the audio HLS has, and audio is wanted.
                return [KhalaStreamSlot(.hls)]
            }
            if webRTC.hasVideo {
                return [KhalaStreamSlot(.webRTC)]
            }
            if hls.hasVideo {
                // Khala: the frontend returns MJPEG here (see above).
                return [KhalaStreamSlot(.hls)]
            }
            // Both streams failed to load.
            return [KhalaStreamSlot(.mjpeg)]
        }
        if hls?.hasVideo != webRTC?.hasVideo {
            // One of the two has loaded or failed: show the one with video, or the one still loading.
            if hls?.hasVideo == true {
                return [KhalaStreamSlot(.hls), KhalaStreamSlot(.webRTC, visible: false)]
            }
            if hls?.hasVideo == false {
                return [KhalaStreamSlot(.webRTC)]
            }
            if webRTC?.hasVideo == true {
                return [KhalaStreamSlot(.webRTC), KhalaStreamSlot(.hls, visible: false)]
            }
            if webRTC?.hasVideo == false {
                return [KhalaStreamSlot(.hls)]
            }
        }
        // Neither has reported: both mount, HLS shown (with the poster) while WebRTC negotiates behind it.
        return [KhalaStreamSlot(.hls), KhalaStreamSlot(.webRTC, visible: false)]
    }
}

/// The live page's two lanes (WebRTC and HLS in one WKWebView) run as `ha-camera-stream` runs its two players:
/// both start, the selection decides which one shows, a lane the selection drops is stopped, and a selection of
/// MJPEG means the page gives way to the host's next player. Events in, effects out, no I/O.
struct KhalaLiveStage: Equatable {
    enum Effect: Equatable {
        case startLane(KhalaStreamKind)
        case stopLane(KhalaStreamKind)
        /// Bring this lane's video to the front.
        case show(KhalaStreamKind)
        /// Neither lane can play: the host moves on (AVPlayer HLS, then MJPEG).
        case giveUp
    }

    /// The lanes on offer (`KhalaLiveLanes`), as stream types.
    let supported: [KhalaStreamKind]
    private(set) var muted: Bool
    private(set) var hls: KhalaStreamReport?
    private(set) var webRTC: KhalaStreamReport?
    private(set) var running: Set<KhalaStreamKind> = []
    private(set) var playing: Set<KhalaStreamKind> = []
    /// The lane on screen.
    private(set) var front: KhalaStreamKind?
    private(set) var hasGivenUp = false

    init(supported: [KhalaStreamKind], muted: Bool) {
        self.supported = supported
        self.muted = muted
    }

    var slots: [KhalaStreamSlot] {
        KhalaStreamSelection.streams(supported: supported, hls: hls, webRTC: webRTC, muted: muted)
    }

    /// The loader shows until the lane on screen has a frame (and stays while the host moves on after a give-up).
    var isLoading: Bool {
        guard let front else { return true }
        return !playing.contains(front)
    }

    /// A fresh race: every report forgotten, as the frontend's `_getCapabilities` does for a new camera.
    mutating func start() -> [Effect] {
        hls = nil
        webRTC = nil
        playing = []
        hasGivenUp = false
        let stopped = running.sorted { $0.rawValue < $1.rawValue }.map { Effect.stopLane($0) }
        running = []
        front = nil
        return stopped + reconcile()
    }

    /// Everything stops; nothing starts until `start()`.
    mutating func stop() -> [Effect] {
        let stopped = running.sorted { $0.rawValue < $1.rawValue }.map { Effect.stopLane($0) }
        running = []
        playing = []
        front = nil
        return stopped
    }

    mutating func report(_ kind: KhalaStreamKind, _ report: KhalaStreamReport) -> [Effect] {
        guard running.contains(kind) else { return [] }
        switch kind {
        case .hls: hls = report
        case .webRTC: webRTC = report
        case .mjpeg: return []
        }
        if !report.hasVideo { playing.remove(kind) }
        return reconcile()
    }

    mutating func setPlaying(_ kind: KhalaStreamKind, _ isPlaying: Bool) -> [Effect] {
        guard running.contains(kind) else { return [] }
        if isPlaying { playing.insert(kind) } else { playing.remove(kind) }
        return []
    }

    mutating func setMuted(_ muted: Bool) -> [Effect] {
        self.muted = muted
        return reconcile()
    }

    private mutating func reconcile() -> [Effect] {
        guard !hasGivenUp else { return [] }
        let slots = self.slots
        if slots.contains(where: { $0.kind == .mjpeg }) || slots.isEmpty {
            hasGivenUp = true
            let effects = stop()
            return effects + [.giveUp]
        }
        let wanted = Set(slots.map(\.kind))
        var effects: [Effect] = []
        for kind in [KhalaStreamKind.hls, .webRTC] where running.contains(kind) && !wanted.contains(kind) {
            running.remove(kind)
            playing.remove(kind)
            effects.append(.stopLane(kind))
        }
        // In the selection's order: the lane on screen starts first.
        for slot in slots where !running.contains(slot.kind) {
            running.insert(slot.kind)
            effects.append(.startLane(slot.kind))
        }
        let shown = slots.first(where: \.visible)?.kind
        if shown != front {
            front = shown
            if let shown { effects.append(.show(shown)) }
        }
        return effects
    }
}

/// The frontend keeps a hidden stream for 60 s (`HIDDEN_CLEANUP_DELAY`) before cleaning it up, and leaves a stream
/// in picture in picture alone, so a quick trip to another app comes back to the stream still running. Two
/// differences, both because an iOS app is suspended in the background (its timers stop and fire late):
/// a stream not yet playing is cleaned up at once (its negotiation deadlines cannot be trusted across a
/// suspension), and the elapsed time is checked on return rather than trusted to the timer.
struct KhalaLiveVisibility: Equatable {
    enum Action: Equatable {
        /// Nothing to do: the stream stays as it is.
        case keep
        case armCleanup(token: Int, after: TimeInterval)
        /// Stop every lane; the player resumes on return.
        case cleanUp
        /// Back after a clean-up: start again.
        case resume
        /// Back after longer than the delay while the timer never ran: clean up and start again.
        case restart
    }

    /// `HIDDEN_CLEANUP_DELAY` in `ha-web-rtc-player.ts` and `ha-hls-player.ts`.
    var cleanupDelay: TimeInterval = 60
    private(set) var hiddenSince: Date?
    private(set) var token = 0
    private(set) var isCleanedUp = false
    private(set) var isPictureInPicture = false

    var isHidden: Bool { hiddenSince != nil || isCleanedUp }

    mutating func backgrounded(at date: Date, isPlaying: Bool) -> Action {
        // "video is playing in picture-in-picture mode, don't do anything".
        guard !isPictureInPicture, hiddenSince == nil, !isCleanedUp else { return .keep }
        guard isPlaying else {
            isCleanedUp = true
            return .cleanUp
        }
        hiddenSince = date
        token += 1
        return .armCleanup(token: token, after: cleanupDelay)
    }

    mutating func cleanupDeadline(token: Int) -> Action {
        guard token == self.token, hiddenSince != nil, !isCleanedUp else { return .keep }
        isCleanedUp = true
        return .cleanUp
    }

    mutating func foregrounded(at date: Date) -> Action {
        let since = hiddenSince
        let cleaned = isCleanedUp
        hiddenSince = nil
        isCleanedUp = false
        token += 1
        if cleaned { return .resume }
        // "stream was not cleaned up yet, just cancel the cleanup" — unless the delay passed while suspended.
        if let since, date.timeIntervalSince(since) >= cleanupDelay { return .restart }
        return .keep
    }

    /// The websocket went while hidden: the server closed the session with it, so there is nothing to keep.
    mutating func socketLost() -> Action {
        guard hiddenSince != nil, !isCleanedUp else { return .keep }
        isCleanedUp = true
        return .cleanUp
    }

    /// Picture in picture keeps a stream alive in the background; leaving it there starts the hidden clock.
    mutating func pictureInPicture(_ active: Bool, inBackground: Bool, at date: Date, isPlaying: Bool) -> Action {
        isPictureInPicture = active
        guard !active, inBackground else { return .keep }
        return backgrounded(at: date, isPlaying: isPlaying)
    }
}

/// `ha-hls-player.ts` `_startHls`: the frontend fetches the master playlist itself, plays its one media playlist
/// directly (sparing the player a second round trip) and reports audio and video from its CODECS.
struct KhalaHLSPlaylist: Equatable {
    /// The media playlist when the master lists exactly one, else the master itself.
    let playlistURL: URL
    /// The two CODECS entries' first components ("hvc1", "mp4a"), "undefined" where the frontend's pattern found
    /// none — kept as the frontend computes them, so the report matches.
    let codecs: [String]?
    /// The video codec for the badge ("H.265"), from the full CODECS attribute.
    let videoCodec: String?

    var report: KhalaStreamReport {
        // `_reportStreams`.
        guard let codecs else { return .failed }
        let hasAudio = codecs.contains("mp4a")
        return KhalaStreamReport(hasAudio: hasAudio, hasVideo: hasAudio ? codecs.count > 1 : !codecs.isEmpty)
    }

    /// The frontend's `playlistRegexp`, unchanged:
    /// `/#EXT-X-STREAM-INF:.*?(?:CODECS=".*?([^.]*)?\..*?,([^.]*)?\..*?".*?)?(?:\n|\r\n)(.+)/g`.
    private static let pattern = #"#EXT-X-STREAM-INF:.*?(?:CODECS=".*?([^.]*)?\..*?,([^.]*)?\..*?".*?)?(?:\n|\r\n)(.+)"#

    init(master: String, url: URL) {
        let regex = try? NSRegularExpression(pattern: Self.pattern)
        let range = NSRange(master.startIndex ..< master.endIndex, in: master)
        let matches = regex?.matches(in: master, range: range) ?? []
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: master) else { return nil }
            return String(master[range])
        }
        let first = matches.first
        if let first, matches.count == 1, let path = group(first, 3),
           let media = URL(string: path.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: url) {
            // Only the regular playlist when the master names exactly one.
            playlistURL = media.absoluteURL
        } else {
            playlistURL = url
        }
        codecs = first.map { [group($0, 1) ?? "undefined", group($0, 2) ?? "undefined"] }
        videoCodec = Self.videoCodec(in: master)
    }

    /// The first video entry of the first CODECS attribute, as the badge names it.
    static func videoCodec(in master: String) -> String? {
        guard let start = master.range(of: "CODECS=\"") else { return nil }
        let rest = master[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        for entry in rest[..<end].split(separator: ",") {
            let family = entry.split(separator: ".").first.map { String($0).lowercased() } ?? ""
            switch family {
            case "hvc1", "hev1": return "H.265"
            case "avc1", "avc3": return "H.264"
            case "av01": return "AV1"
            case "vp09": return "VP9"
            default: continue
            }
        }
        return nil
    }
}
