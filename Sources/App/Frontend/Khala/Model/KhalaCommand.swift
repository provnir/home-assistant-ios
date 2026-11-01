import Foundation

/// A one-shot command a control offers next to others (vacuum start/pause/home/locate, cover open/stop/close).
enum KhalaCommand: String, Hashable {
    case start
    case pause
    case stop
    case returnHome
    case locate
    case open
    case close
}
