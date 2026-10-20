import SwiftUI

/// Interim Cameras screen: every camera in a wrapping vertical list (never side-scrolling), each opening the app's
/// existing native camera player. The designed camera screen (live view, events, switcher) comes later.
struct KhalaCamerasView: View {
    let cameras: [KhalaEntity]
    let onMenu: () -> Void
    let onCamera: (KhalaEntity) -> Void

    var body: some View {
        KhalaScreen(
            title: KhalaText.cameras,
            subtitle: KhalaText.cameraCount(cameras.count),
            onMenu: onMenu
        ) {
            LazyVStack(spacing: 12) {
                ForEach(cameras, id: \.entityId) { camera in
                    KhalaUpcomingCard(
                        title: camera.name,
                        subtitle: KhalaText.humanized(state: camera.state),
                        category: .security
                    ) {
                        onCamera(camera)
                    }
                }
            }
        }
    }
}

#Preview {
    KhalaCamerasView(
        cameras: [
            KhalaEntity(entityId: "camera.porch", state: "idle", lastChanged: Date(), attributes: ["friendly_name": "Porch"]),
            KhalaEntity(entityId: "camera.yard", state: "recording", lastChanged: Date(), attributes: ["friendly_name": "Yard"]),
        ],
        onMenu: {},
        onCamera: { _ in }
    )
    .background(KhalaGround())
}
