import Combine
import Foundation

/// The live entity states and registry facts the device screens read. Kept apart from `KhalaHomeViewModel`'s
/// published values so a sensor ticking somewhere only re-renders the device screen on display, never Today or
/// the menu. Filled by `KhalaHomeViewModel` from the same websocket subscription.
@MainActor
final class KhalaLiveStates: ObservableObject {
    @Published private(set) var entities: [KhalaEntity] = []
    @Published private(set) var entitiesById: [String: KhalaEntity] = [:]
    /// Raw attributes by entity id (`source_list`, `supported_features`, `min`/`max`...).
    @Published private(set) var attributes: [String: [String: Any]] = [:]
    /// The integration of each entity, from the entity registry (`switcher_kis`, `tesla_fleet`...).
    @Published private(set) var platforms: [String: String] = [:]
    /// Registry device model by device id ("Model 3").
    @Published private(set) var deviceModels: [String: String] = [:]
    /// `automation/config` answers by automation entity id.
    @Published private(set) var automationConfigs: [String: [String: Any]] = [:]

    func update(entities: [KhalaEntity], attributes: [String: [String: Any]]) {
        self.entities = entities
        entitiesById = Dictionary(entities.map { ($0.entityId, $0) }, uniquingKeysWith: { first, _ in first })
        self.attributes = attributes
    }

    func update(platforms: [String: String], deviceModels: [String: String]) {
        if platforms != self.platforms { self.platforms = platforms }
        if deviceModels != self.deviceModels { self.deviceModels = deviceModels }
    }

    func update(automationConfigs: [String: [String: Any]]) {
        self.automationConfigs = automationConfigs
    }

    func members(of device: KhalaDevice) -> [KhalaEntity] {
        device.memberEntityIds.compactMap { entitiesById[$0] }
    }
}
