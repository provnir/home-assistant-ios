import Shared
import SwiftUI

/// The native screen for a destination that isn't one of the menu's own (`KhalaDestination.camera/.device/.entity`):
/// picks the designed screen for the device's role — car, hot water — or the template screen (`KhalaTemplateScreen`:
/// lights, fans, switches and everything else).
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
                onFullScreen: { entityId, name in shell.openCamera(entityId: entityId, name: name) },
                onCapture: { camera, date in
                    shell.openCapture(cameraEntityId: camera.entityId, cameraName: camera.name, date: date) {}
                }
            )
            .id(entityId)
        case let .device(id):
            if let device = home.devices.first(where: { $0.id == id }) {
                switch device.category {
                case .car:
                    KhalaCarView(
                        device: device,
                        live: live,
                        pending: live.pending,
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
                    template(device.name, category: device.category, primary: device.primaryEntityId,
                             members: device.memberEntityIds, actions: actions)
                }
            } else {
                template(KhalaText.devicesTitle, category: .neutral, primary: "", members: [], actions: actions)
            }
        case let .entity(entityId):
            template(live.entitiesById[entityId]?.name ?? entityId, category: Self.category(ofEntity: entityId,
                                                                                            live: live),
                     primary: entityId, members: [entityId], actions: actions)
        case .today, .cameras, .automations, .dashboards, .settings:
            EmptyView()
        }
    }

    private func template(
        _ title: String,
        category: KhalaCategory,
        primary: String,
        members: [String],
        actions: KhalaScreenActions
    ) -> some View {
        KhalaTemplateScreen(
            title: title,
            category: category,
            primaryEntityId: primary,
            memberEntityIds: members,
            live: live,
            actions: actions,
            calendar: home.calendar,
            onOpenEntity: { entityId in
                shell.route(KhalaRouting.target(
                    forEntityId: entityId,
                    entities: live.entities,
                    devices: home.devices,
                    automationConfigs: live.automationConfigs
                ))
            }
        )
        // A member opened from its group gets a fresh screen, not the group's scroll position.
        .id(primary)
    }

    /// A lone entity's colour: its kind's when it has a template of its own (a light is amber), else neutral as in
    /// 41.1.
    private static func category(ofEntity entityId: String, live: KhalaLiveStates) -> KhalaCategory {
        guard let entity = live.entitiesById[entityId] else { return .neutral }
        let descriptor = KhalaDescriptors.shown(for: entity, attributes: live.attributes[entityId])
        return descriptor.template == .generic ? .neutral : descriptor.accent
    }
}
