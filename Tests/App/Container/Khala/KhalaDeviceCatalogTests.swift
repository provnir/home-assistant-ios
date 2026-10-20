import Foundation
@testable import HomeAssistant
import Testing

struct KhalaDeviceCatalogTests {
    private typealias Fixtures = KhalaTestFixtures

    @Test func detectsDevicesFromTheirEntities() {
        let devices = KhalaDeviceCatalog.build(entities: Fixtures.home, assignments: [])
        #expect(devices.map(\.name) == ["Rover", "Den", "Kitchen speaker", "Relay 7"])
        #expect(devices.map(\.category) == [.car, .media, .media, .neutral])
        #expect(devices.map(\.stateText) == ["72%", "Off", "Playing", "Off"])
    }

    @Test func carShowsItsBatteryAndKeepsItsSwitchesAndPlayer() throws {
        let car = try #require(KhalaDeviceCatalog.build(entities: Fixtures.home, assignments: []).first)
        #expect(car.primaryEntityId == "sensor.rover_battery_level")
        #expect(car.memberEntityIds.contains("switch.rover_defrost"))
        #expect(car.memberEntityIds.contains("media_player.rover_media"))
    }

    @Test func receiverIsTheFaceOfItsDevice() throws {
        let den = try #require(KhalaDeviceCatalog.build(entities: Fixtures.home, assignments: []).first { $0.name == "Den" })
        #expect(den.primaryEntityId == "media_player.den_receiver")
    }

    @Test func phonesAndCamerasAreNotListed() {
        let names = KhalaDeviceCatalog.build(entities: Fixtures.home, assignments: []).map(\.name)
        #expect(!names.contains("Phone"))
        #expect(!names.contains("Porch"))
        #expect(KhalaDeviceCatalog.cameras(in: Fixtures.home).map(\.name) == ["Porch", "Yard"])
    }

    @Test func assignmentPinsAndTakesOverItsDevice() {
        let assignments = [KhalaRoleAssignment(entityId: "switch.relay_7", role: .heat, label: " Hot water ")]
        let devices = KhalaDeviceCatalog.build(entities: Fixtures.home, assignments: assignments)
        #expect(devices.first?.name == "Hot water")
        #expect(devices.first?.category == .heat)
        #expect(devices.first?.isPinned == true)
        #expect(!devices.contains { $0.name == "Relay 7" })
    }

    @Test func assignmentToAMissingEntityIsIgnored() {
        let assignments = [KhalaRoleAssignment(entityId: "switch.gone", role: .heat, label: nil)]
        let devices = KhalaDeviceCatalog.build(entities: Fixtures.home, assignments: assignments)
        #expect(devices.allSatisfy { !$0.isPinned })
    }

    @Test func entitiesWithoutADeviceStandAlone() {
        let loose = [Fixtures.entity("switch.template_fan", "on", ["friendly_name": "Fan"])]
        let devices = KhalaDeviceCatalog.build(entities: loose, assignments: [])
        #expect(devices.map(\.id) == ["entity:switch.template_fan"])
        #expect(devices.first?.stateText == "On")
    }

    @Test func auxiliaryEntitiesAreNeverAFace() {
        let relay = [Fixtures.entity("switch.relay_9", "off", [:], device: "d9", deviceName: "Relay 9", auxiliary: true)]
        #expect(KhalaDeviceCatalog.build(entities: relay, assignments: []).isEmpty)
    }

    @Test func roleAssignmentsRoundTripPerServer() throws {
        let suite = "khala-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = KhalaRoleAssignmentStore(defaults: defaults)
        let assignments = [KhalaRoleAssignment(entityId: "switch.relay_7", role: .heat, label: "Hot water")]
        store.save(assignments, serverId: "a")
        #expect(store.load(serverId: "a") == assignments)
        #expect(store.load(serverId: "b").isEmpty)
        store.save([], serverId: "a")
        #expect(store.load(serverId: "a").isEmpty)
    }
}
