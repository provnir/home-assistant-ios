import Foundation

/// Which engine the live view starts on. A hidden testing setting (App settings → General → Khala); `auto` is
/// the default and the only one Nir needs.
enum KhalaLiveEngine: String, CaseIterable, Equatable {
    /// The WebKit page racing WebRTC and HLS as the frontend does; after two WebRTC failures on a camera in this
    /// app session, the page runs its HLS lane only. Then AVPlayer HLS, then MJPEG.
    case auto
    /// The WebKit page with both lanes, always (the fallback memory is ignored).
    case webKit
    /// Never the WebKit page: straight to AVPlayer HLS, then MJPEG.
    case hls

    static let defaultsKey = "khala.liveEngine"

    init(stored: String?) {
        self = stored.flatMap(KhalaLiveEngine.init(rawValue:)) ?? .auto
    }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .webKit: return "WebKit"
        case .hls: return "HLS"
        }
    }

    /// The players to try, given the camera's own plan (`CameraStreamPlan`, most preferred first). The `webRTC`
    /// slot is the WebKit page. It is dropped when this engine says so, or when the page would have no lane left
    /// to run (`lanes`), but a camera is never left with nothing to play.
    func plan<Player: Equatable>(_ players: [Player], webRTC: Player, hls: Player, webKitFailedRepeatedly: Bool) -> [Player] {
        let skip: Bool
        switch self {
        case .auto: skip = webKitFailedRepeatedly && !players.contains(hls)
        case .webKit: skip = false
        case .hls: skip = true
        }
        guard skip else { return players }
        let rest = players.filter { $0 != webRTC }
        return rest.isEmpty ? players : rest
    }

    /// What the WebKit page runs for this camera: its WebRTC lane unless `auto` has seen WebRTC fail repeatedly
    /// here, and its HLS lane whenever the camera offers HLS (`frontend_stream_types`).
    func lanes<Player: Equatable>(_ players: [Player], webRTC: Player, hls: Player, webKitFailedRepeatedly: Bool)
        -> KhalaLiveLanes {
        let offersWebRTC = players.contains(webRTC)
        let webRTCLane: Bool
        switch self {
        case .auto: webRTCLane = offersWebRTC && !webKitFailedRepeatedly
        case .webKit, .hls: webRTCLane = offersWebRTC
        }
        let lanes = KhalaLiveLanes(webRTC: webRTCLane, hls: players.contains(hls))
        // A camera whose only lane was dropped still gets its WebRTC: the plan kept the slot for it.
        return lanes.isEmpty ? KhalaLiveLanes(webRTC: offersWebRTC, hls: false) : lanes
    }
}

/// The lanes the WebKit live page runs, as the frontend's `frontend_stream_types` (the order does not matter:
/// `KhalaStreamSelection` decides).
struct KhalaLiveLanes: Equatable {
    var webRTC: Bool
    var hls: Bool

    var isEmpty: Bool { !webRTC && !hls }

    var streamKinds: [KhalaStreamKind] {
        (hls ? [.hls] : []) + (webRTC ? [.webRTC] : [])
    }
}

/// The app session's record of WebKit live failures per camera: after `limit` (two) WebRTC-lane failures that say
/// something about WebKit (`KhalaLiveFailure.countsAgainstWebKit`), `auto` runs that camera on HLS only until the
/// app is relaunched. Memory only, never persisted.
struct KhalaLiveFallbackMemory: Equatable {
    var limit = 2
    private(set) var failures: [String: Int] = [:]
    /// The last give-up, for the settings row: camera and reason (already redacted).
    private(set) var lastFallback: String?

    mutating func record(_ failure: KhalaLiveFailure, cameraEntityId: String) {
        lastFallback = "\(cameraEntityId): \(failure.logDescription)"
        guard failure.countsAgainstWebKit else { return }
        failures[cameraEntityId, default: 0] += 1
    }

    func skipsWebKit(cameraEntityId: String) -> Bool {
        failures[cameraEntityId, default: 0] >= limit
    }

    mutating func reset() {
        failures = [:]
        lastFallback = nil
    }
}
