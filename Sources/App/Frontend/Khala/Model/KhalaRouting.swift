import Foundation

/// Decides which native screen a tap opens, from Home Assistant data only:
/// - a camera, or an event entity on a camera's device → that camera's screen;
/// - a listed device (or any of its entities) → its screen; media devices open the media sheet instead;
/// - an automation → the screen of the device it acts on, else Automations;
/// - anything else → the generic entity screen.
enum KhalaRouting {
    static func target(for device: KhalaDevice, cameras: [KhalaEntity]) -> KhalaRouteTarget {
        switch device.category {
        case .media:
            return .mediaSheet(deviceId: device.id)
        case .security:
            // A pinned camera-side entity: its camera if the device has one.
            if let camera = cameras.first(where: { device.memberEntityIds.contains($0.entityId) }) {
                return .screen(.camera(entityId: camera.entityId))
            }
            return .screen(.device(id: device.id))
        case .car, .heat, .neutral, .sun:
            return .screen(.device(id: device.id))
        }
    }

    static func target(
        forEntityId entityId: String,
        entities: [KhalaEntity],
        devices: [KhalaDevice],
        automationConfigs: [String: [String: Any]]
    ) -> KhalaRouteTarget {
        let domain = entityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? entityId
        let cameras = entities.filter { $0.domain == "camera" }
        if domain == "camera" {
            return .screen(.camera(entityId: entityId))
        }
        if domain == "event", let camera = camera(forEvent: entityId, entities: entities) {
            return .screen(.camera(entityId: camera.entityId))
        }
        if let device = devices.first(where: { $0.primaryEntityId == entityId })
            ?? devices.first(where: { $0.memberEntityIds.contains(entityId) }) {
            return target(for: device, cameras: cameras)
        }
        if domain == "automation" {
            let byId = Dictionary(entities.map { ($0.entityId, $0) }, uniquingKeysWith: { first, _ in first })
            if let config = automationConfigs[entityId] {
                let targets = KhalaAutomationSchedule.referencedEntityIds(config: config, entities: byId)
                for target in targets {
                    if let device = devices.first(where: { $0.memberEntityIds.contains(target) }) {
                        return self.target(for: device, cameras: cameras)
                    }
                }
            }
            return .screen(.automations)
        }
        return .screen(.entity(entityId: entityId))
    }

    /// The camera on the same registry device as an event entity, or — without registry data — the camera whose
    /// name starts the event's name ("Porch" for "Porch Field detection").
    static func camera(forEvent eventEntityId: String, entities: [KhalaEntity]) -> KhalaEntity? {
        guard let event = entities.first(where: { $0.entityId == eventEntityId }) else { return nil }
        let cameras = entities.filter { $0.domain == "camera" }
        if let deviceId = event.deviceId, let camera = cameras.first(where: { $0.deviceId == deviceId }) {
            return camera
        }
        return cameras
            .filter { event.name.hasPrefix($0.name + " ") }
            .max { $0.name.count < $1.name.count }
    }
}
