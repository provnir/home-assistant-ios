import Foundation

/// Which engine the live view starts on. A hidden testing setting (App settings → General → Khala); `auto` is
/// the default and the only one Nir needs.
enum KhalaLiveEngine: String, CaseIterable, Equatable {
    /// WebKit WebRTC first, unless it already failed twice on this camera in this app session; then HLS, MJPEG.
    case auto
    /// WebKit WebRTC first, always (the fallback memory is ignored).
    case webKit
    /// Never WebRTC: straight to HLS, then MJPEG.
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

    /// The players to try, given the camera's own plan (`CameraStreamPlan`, most preferred first). Drops WebRTC
    /// when this engine (or the memory, for `auto`) says so, but never leaves a camera with nothing to play.
    func plan<Player: Equatable>(_ players: [Player], webRTC: Player, webKitFailedRepeatedly: Bool) -> [Player] {
        let skip: Bool
        switch self {
        case .auto: skip = webKitFailedRepeatedly
        case .webKit: skip = false
        case .hls: skip = true
        }
        guard skip else { return players }
        let rest = players.filter { $0 != webRTC }
        return rest.isEmpty ? players : rest
    }
}

/// The app session's record of WebKit live failures per camera: after `limit` (two) failures that say something
/// about WebKit (`KhalaLiveFailure.countsAgainstWebKit`), `auto` goes straight to HLS for that camera until the
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
