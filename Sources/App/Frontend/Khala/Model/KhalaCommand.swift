import Foundation

/// A one-shot command a control offers next to others (vacuum start/pause/home/locate, cover open/stop/close and
/// tilt, a lock's open).
enum KhalaCommand: String, Hashable {
    case start
    case pause
    case stop
    case returnHome
    case locate
    case open
    case close
    /// A cover's slats (`open_cover_tilt` / `stop_cover_tilt` / `close_cover_tilt`).
    case openTilt
    case stopTilt
    case closeTilt

    /// A tilt command (its own control beside the cover's open/stop/close).
    var isTilt: Bool {
        [.openTilt, .stopTilt, .closeTilt].contains(self)
    }
}
