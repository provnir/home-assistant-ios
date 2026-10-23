import SFSafeSymbols
import SwiftUI
import UIKit

/// A camera still — the live frame at the stream's resolution, or the server's — full screen on the shared zoomable
/// still viewer (`KhalaStillViewer`), with the share sheet (save to Photos, send...). Presented with
/// `khalaStillCover(item:content:)` from the camera screen's Snapshot button and the live player's.
struct KhalaSnapshotViewer: View {
    let snapshot: KhalaSnapshot
    let onClose: () -> Void

    @State private var index = 0

    var body: some View {
        let title = snapshot.cameraName.isEmpty ? KhalaScreenText.snapshot : snapshot.cameraName
        KhalaStillViewer(
            title: title,
            stills: [KhalaStill(id: snapshot.id.uuidString, image: snapshot.image, accessibilityLabel: title)],
            index: $index,
            onClose: onClose
        )
    }
}

#Preview {
    KhalaSnapshotViewer(
        snapshot: KhalaSnapshot(image: UIImage(systemSymbol: .photo), cameraName: "Camera"),
        onClose: {}
    )
}
