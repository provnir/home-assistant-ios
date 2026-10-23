import UIKit

/// One page of the still viewer (`KhalaStillViewer`): a capture or a snapshot, its full-size image once loaded.
struct KhalaStill: Identifiable {
    let id: String
    /// `nil` while it loads (the page shows a spinner).
    let image: UIImage?
    /// What VoiceOver reads for the page: the camera and the time.
    let accessibilityLabel: String
}
