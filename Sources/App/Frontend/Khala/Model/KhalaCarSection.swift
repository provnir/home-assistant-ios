import Foundation

/// The car screen's tabs, as the hints file names them; `more` is the Overview's "More" menu.
enum KhalaCarSection: String, Equatable {
    case overview, climate, charging, more
    /// A section this build doesn't know (a newer hints file): skipped, so the control falls back to Overview.
    case unknown
}
