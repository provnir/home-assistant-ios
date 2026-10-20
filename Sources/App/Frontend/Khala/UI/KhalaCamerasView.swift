import Shared
import SwiftUI

/// Cameras (menu destination): every camera as a tile in a wrapping two-column grid (never side-scrolling), each
/// opening that camera's native screen.
struct KhalaCamerasView: View {
    let cameras: [KhalaEntity]
    @ObservedObject var live: KhalaLiveStates
    let actions: KhalaScreenActions
    let now: Date
    let calendar: Calendar
    let onMenu: () -> Void
    let onCamera: (String) -> Void

    var body: some View {
        let rows = KhalaCameraCatalog.rows(cameras: cameras, entities: live.entities, now: now, calendar: calendar)
        KhalaScreen(
            title: KhalaText.cameras,
            subtitle: KhalaText.cameraCount(rows.count),
            onMenu: onMenu
        ) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(rows) { row in
                    KhalaCameraTile(row: row, actions: actions) {
                        onCamera(row.entityId)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    KhalaCamerasView(
        cameras: [
            KhalaEntity(entityId: "camera.porch", state: "idle", lastChanged: Date(), attributes: ["friendly_name": "Porch"]),
            KhalaEntity(entityId: "camera.yard", state: "idle", lastChanged: Date(), attributes: ["friendly_name": "Yard"]),
        ],
        live: KhalaLiveStates(),
        actions: KhalaScreenActions(server: ServerFixture.standard),
        now: Date(),
        calendar: .current,
        onMenu: {},
        onCamera: { _ in }
    )
    .background(KhalaGround())
}
#endif
