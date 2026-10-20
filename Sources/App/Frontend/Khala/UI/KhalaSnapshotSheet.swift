import SwiftUI
import UIKit

/// Shows a camera still and offers the share sheet (save to Photos, send...).
struct KhalaSnapshotSheet: View {
    let snapshot: KhalaSnapshot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Image(uiImage: snapshot.image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(16)
                .frame(maxHeight: .infinity)
                .navigationTitle(snapshot.cameraName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(KhalaScreenText.close) { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(
                            item: Image(uiImage: snapshot.image),
                            preview: SharePreview(snapshot.cameraName, image: Image(uiImage: snapshot.image))
                        )
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
