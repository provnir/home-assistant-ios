import Shared
import SwiftUI

/// The native screen for a destination that isn't one of the menu's own (`KhalaDestination.camera/.device/.entity`):
/// picks the designed screen for the device's role — car, hot water — or the generic one.
struct KhalaDetailScreen: View {
    let destination: KhalaDestination
    let server: Server
    @ObservedObject var home: KhalaHomeViewModel
    @ObservedObject var live: KhalaLiveStates
    let shell: KhalaShellModel

    var body: some View {
        let actions = KhalaScreenActions(server: server)
        switch destination {
        case let .camera(entityId):
            KhalaCameraView(
                cameraEntityId: entityId,
                server: server,
                live: live,
                actions: actions,
                now: home.now,
                calendar: home.calendar,
                onSelectCamera: { shell.show(.camera(entityId: $0)) },
                onAllCameras: { shell.show(.cameras) },
                onFullScreen: { entityId, name in shell.openCamera(entityId: entityId, name: name) }
            )
            .id(entityId)
        case let .device(id):
            if let device = home.devices.first(where: { $0.id == id }) {
                switch device.category {
                case .car:
                    KhalaCarView(
                        device: device,
                        live: live,
                        actions: actions,
                        calendar: home.calendar,
                        onMedia: { entityId in shell.route(.mediaSheet(deviceId: device.id, entityId: entityId)) }
                    )
                case .heat:
                    KhalaWaterView(
                        device: device,
                        live: live,
                        actions: actions,
                        now: home.now,
                        calendar: home.calendar
                    )
                case .media, .security, .sun, .neutral:
                    generic(device.name, category: device.category, primary: device.primaryEntityId,
                            members: device.memberEntityIds, actions: actions)
                }
            } else {
                generic(KhalaText.devicesTitle, category: .neutral, primary: "", members: [], actions: actions)
            }
        case let .entity(entityId):
            generic(live.entitiesById[entityId]?.name ?? entityId, category: .neutral, primary: entityId,
                    members: [entityId], actions: actions)
        case .today, .cameras, .automations, .dashboards, .settings:
            EmptyView()
        }
    }

    private func generic(
        _ title: String,
        category: KhalaCategory,
        primary: String,
        members: [String],
        actions: KhalaScreenActions
    ) -> some View {
        KhalaGenericDeviceView(
            title: title,
            category: category,
            primaryEntityId: primary,
            memberEntityIds: members,
            live: live,
            actions: actions,
            calendar: home.calendar
        )
    }
}
