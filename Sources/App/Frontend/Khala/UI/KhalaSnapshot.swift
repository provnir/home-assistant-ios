import UIKit

/// A still the camera screen fetched for sharing.
struct KhalaSnapshot: Identifiable {
    let id = UUID()
    let image: UIImage
    let cameraName: String
}
