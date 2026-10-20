import Combine
import Foundation
import HAKit
import Shared

/// Feeds Khala from the server: live entity states over the HAKit websocket cache, registry facts (devices,
/// hidden/diagnostic flags) from the app database, automation configs for scheduled rows, and the user's role
/// assignments. Everything it publishes is built by the Foundation-only model (`KhalaTimeline`,
/// `KhalaDeviceCatalog`).
@MainActor
final class KhalaHomeViewModel: ObservableObject {
    @Published private(set) var timeline: KhalaTimeline = .empty
    @Published private(set) var devices: [KhalaDevice] = []
    @Published private(set) var cameras: [KhalaEntity] = []
    @Published private(set) var automationCount = 0
    @Published private(set) var userName: String?
    @Published private(set) var assignments: [KhalaRoleAssignment]
    @Published private(set) var now: Date
    /// Display names of every entity with a state, for the device settings list.
    @Published private(set) var entityNames: [String: String] = [:]

    let server: Server
    var calendar: Calendar { Current.calendar() }
    /// Live states and registry facts for the device screens, published on their own (see `KhalaLiveStates`).
    let live = KhalaLiveStates()

    /// Registry facts for one entity, copied out of the app database.
    private struct RegistryFacts {
        let deviceId: String?
        let deviceName: String?
        let isAuxiliary: Bool
        let platform: String?
    }

    private var entities: [KhalaEntity] = []
    private var latestStates: HACachedStates?
    private var registry: [String: RegistryFacts] = [:]
    private var automationConfigs: [String: [String: Any]] = [:]
    private var requestedAutomationConfigs = Set<String>()
    private var tokens: [HACancellable] = []
    private var clock: AnyCancellable?
    private let assignmentStore: KhalaRoleAssignmentStore

    init(server: Server, assignmentStore: KhalaRoleAssignmentStore = KhalaRoleAssignmentStore(defaults: prefs)) {
        self.server = server
        self.assignmentStore = assignmentStore
        self.assignments = assignmentStore.load(serverId: server.identifier.rawValue)
        self.now = Current.date()
    }

    deinit {
        tokens.forEach { $0.cancel() }
    }

    // MARK: - Lifecycle

    func start() {
        if clock == nil {
            clock = Timer.publish(every: 30, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.tick()
                }
        }
        loadRegistry()
        subscribeIfNeeded()
    }

    func stop() {
        tokens.forEach { $0.cancel() }
        tokens.removeAll()
        clock = nil
    }

    /// Retried on every tick: the server may have had no usable URL yet when the screen appeared.
    private func subscribeIfNeeded() {
        guard tokens.isEmpty, let api = Current.api(for: server) else { return }
        // Same subscription shape as `CarPlaySceneDelegate.subscribeToEntitiesChanges`, without its forced
        // reconnect: this screen shares the connection with everything else in the app.
        api.connectWebSocketIfNeeded()
        tokens.append(api.connection.caches.states().subscribe { [weak self] _, states in
            Task { @MainActor [weak self] in
                self?.apply(states)
            }
        })
        tokens.append(api.connection.caches.user.subscribe { [weak self] _, user in
            Task { @MainActor [weak self] in
                self?.userName = user.name
            }
        })
    }

    // MARK: - Role assignments

    func setAssignments(_ newValue: [KhalaRoleAssignment]) {
        assignments = newValue
        assignmentStore.save(newValue, serverId: server.identifier.rawValue)
        rebuild()
    }

    // MARK: - Building

    private func tick() {
        now = Current.date()
        subscribeIfNeeded()
        if registry.isEmpty {
            // The database updater may not have run yet on a fresh install; pick the registry up once it has.
            loadRegistry()
            if let latestStates { apply(latestStates) }
        }
        rebuild()
    }

    private func apply(_ states: HACachedStates) {
        latestStates = states
        var attributes: [String: [String: Any]] = [:]
        entities = states.all.map { entity -> KhalaEntity in
            let facts = registry[entity.entityId]
            attributes[entity.entityId] = entity.attributes.dictionary
            return KhalaEntity(
                entityId: entity.entityId,
                state: entity.state,
                lastChanged: entity.lastChanged,
                attributes: entity.attributes.dictionary,
                deviceId: facts?.deviceId,
                deviceName: facts?.deviceName,
                isAuxiliary: facts?.isAuxiliary ?? false
            )
        }
        .sorted { $0.entityId < $1.entityId }
        let names = Dictionary(entities.map { ($0.entityId, $0.name) }, uniquingKeysWith: { first, _ in first })
        if names != entityNames { entityNames = names }
        live.update(entities: entities, attributes: attributes)
        fetchMissingAutomationConfigs()
        rebuild()
    }

    private func rebuild() {
        let date = Current.date()
        let newDevices = KhalaDeviceCatalog.build(entities: entities, assignments: assignments)
        let newTimeline = KhalaTimeline.build(
            entities: entities,
            devices: newDevices,
            automationConfigs: automationConfigs,
            now: date,
            calendar: calendar
        )
        let newCameras = KhalaDeviceCatalog.cameras(in: entities)
        let newAutomationCount = entities.filter { $0.domain == "automation" }.count
        if newDevices != devices { devices = newDevices }
        if newTimeline != timeline { timeline = newTimeline }
        if newCameras != cameras { cameras = newCameras }
        if newAutomationCount != automationCount { automationCount = newAutomationCount }
    }

    // MARK: - Data sources

    /// Mirrors `MainWindowGroupCommands`' read of the persisted entity and device registries.
    private func loadRegistry() {
        let serverId = server.identifier.rawValue
        do {
            let entries = try EntityRegistryListForDisplay.Entity.config(serverId: serverId)
            let devices = try AppDeviceRegistry.config(serverId: serverId)
            var deviceNames: [String: String] = [:]
            var deviceModels: [String: String] = [:]
            for device in devices {
                if let name = device.nameByUser ?? device.name {
                    deviceNames[device.deviceId] = name
                }
                if let model = device.model, !model.isEmpty {
                    deviceModels[device.deviceId] = model
                }
            }
            var platforms: [String: String] = [:]
            var facts: [String: RegistryFacts] = [:]
            for entry in entries {
                facts[entry.entityId] = RegistryFacts(
                    deviceId: entry.deviceId,
                    deviceName: entry.deviceId.flatMap { deviceNames[$0] },
                    isAuxiliary: entry.entityCategory != nil || entry.isHidden,
                    platform: entry.platform
                )
                if let platform = entry.platform { platforms[entry.entityId] = platform }
            }
            registry = facts
            live.update(platforms: platforms, deviceModels: deviceModels)
        } catch {
            Current.Log.error("Khala: failed to read the registry for server \(serverId): \(error.localizedDescription)")
        }
    }

    /// One `automation/config` request per automation, once per session (admin-only on the server; a refusal just
    /// leaves that automation off the timeline). Same request shape as `CameraCapabilities.fetch`. Disabled ones
    /// are fetched too, so a device's Schedule can offer to switch them back on; Today skips them itself.
    private func fetchMissingAutomationConfigs() {
        guard let api = Current.api(for: server) else { return }
        let missing = entities
            .filter { $0.domain == "automation" }
            .map(\.entityId)
            .filter { !requestedAutomationConfigs.contains($0) }
        for entityId in missing {
            requestedAutomationConfigs.insert(entityId)
            api.connection.send(.init(
                type: .webSocket("automation/config"),
                data: ["entity_id": entityId]
            )) { [weak self] result in
                switch result {
                case let .success(data):
                    guard case let .dictionary(response) = data,
                          let config = response["config"] as? [String: Any] else { return }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.automationConfigs[entityId] = config
                        self.live.update(automationConfigs: self.automationConfigs)
                        self.rebuild()
                    }
                case let .failure(error):
                    Current.Log.info("Khala: no config for \(entityId): \(error.localizedDescription)")
                }
            }
        }
    }
}
