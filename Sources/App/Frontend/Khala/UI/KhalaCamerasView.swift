import Shared
import SwiftUI

/// Cameras (menu destination): every camera as a tile in a wrapping grid (never side-scrolling), each opening that
/// camera's native screen. Two columns on a phone-sized width; more where the width allows (iPhone Duo's inner
/// display, iPad), see `KhalaColumnMath.tileColumns`.
struct KhalaCamerasView: View {
    let cameras: [KhalaEntity]
    @ObservedObject var live: KhalaLiveStates
    let actions: KhalaScreenActions
    let now: Date
    let calendar: Calendar
    let onMenu: () -> Void
    let onCamera: (String) -> Void

    /// The grid's own width, measured: it changes in place when an iPhone Duo opens or closes.
    @State private var gridWidth: CGFloat = 0
    private static let spacing: CGFloat = 12

    var body: some View {
        let rows = KhalaCameraCatalog.rows(cameras: cameras, entities: live.entities, now: now, calendar: calendar)
        KhalaScreen(
            title: KhalaText.cameras,
            subtitle: KhalaText.cameraCount(rows.count),
            onMenu: onMenu,
            column: .wide
        ) {
            let count = KhalaColumnMath.tileColumns(available: Double(gridWidth), spacing: Double(Self.spacing))
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: count),
                spacing: Self.spacing
            ) {
                ForEach(rows) { row in
                    KhalaCameraTile(row: row, actions: actions) {
                        onCamera(row.entityId)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
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
