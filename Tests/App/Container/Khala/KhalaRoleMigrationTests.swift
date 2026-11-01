import Foundation
@testable import HomeAssistant
import Testing

/// The legacy role → kind decode of `KhalaRoleAssignment` (the one sharp edge of slice 1) and the new fields.
struct KhalaRoleMigrationTests {
    private static func decode(_ json: String) throws -> [KhalaRoleAssignment] {
        try JSONDecoder().decode([KhalaRoleAssignment].self, from: Data(json.utf8))
    }

    @Test func legacyRolesMapToKindsByDomain() throws {
        let pins = try Self.decode(#"""
        [{"entityId":"switch.a","role":"heat"},{"entityId":"lock.b","role":"security"},
         {"entityId":"camera.c","role":"security"},{"entityId":"event.d","role":"security"},
         {"entityId":"media_player.e","role":"media"},{"entityId":"device_tracker.f","role":"car"},
         {"entityId":"light.g","role":"neutral"},{"entityId":"sensor.h","role":"sun"}]
        """#)
        #expect(pins.map(\.kind) == [.waterHeater, .lock, .camera, .camera, .media, .car, .switch, .generic])
        #expect(pins.map(\.role) == [.heat, .security, .security, .security, .media, .car, .neutral, .sun])
        // Every legacy role is its kind's own colour except sun, which is kept as an override.
        #expect(pins.map(\.accent) == [nil, nil, nil, nil, nil, nil, nil, .sun])
    }

    @Test func anUnknownRoleKeepsTheOtherPins() throws {
        let pins = try Self.decode(
            #"[{"entityId":"switch.a","role":"teleporter"},{"entityId":"switch.b","role":"heat"}]"#
        )
        #expect(pins.map(\.role) == [.neutral, .heat])
    }

    @Test func newRecordsKeepKindAndColourAndStillCarryTheLegacyRole() throws {
        let pin = KhalaRoleAssignment(entityId: "light.desk", kind: .light, accent: .heat, label: "Desk")
        let data = try JSONEncoder().encode(pin)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["kind"] as? String == "light")
        #expect(object["accent"] as? String == "heat")
        #expect(object["role"] as? String == "heat")
        #expect(object["label"] as? String == "Desk")
        #expect(try JSONDecoder().decode(KhalaRoleAssignment.self, from: data) == pin)

        let plain = KhalaRoleAssignment(entityId: "light.desk", kind: .light, label: nil)
        let plainObject = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any]
        )
        #expect(plainObject["accent"] == nil)
        #expect(plainObject["label"] == nil)
        #expect(plainObject["role"] as? String == "sun")
        // An accent equal to the kind's own is not stored.
        #expect(KhalaRoleAssignment(entityId: "light.x", kind: .light, accent: .sun, label: nil).accent == nil)
        // A new record with an accent this build doesn't know keeps its kind's colour.
        let future = try Self.decode(#"[{"entityId":"fan.a","kind":"fan","accent":"ultraviolet","role":"neutral"}]"#)
        #expect(future.first?.kind == .fan)
        #expect(future.first?.accent == nil)
    }

    @Test func thePickerSetsTheRoleAndTheKindFollows() {
        var pin = KhalaRoleAssignment(entityId: "lock.front", role: .neutral, label: nil)
        #expect(pin.kind == .switch)
        pin.role = .security
        #expect(pin.kind == .lock)
        #expect(pin.accent == nil)
        pin.role = .heat
        #expect(pin.kind == .waterHeater)
        #expect(pin.role == .heat)
    }

    @Test func registryFactsReachTheDevice() {
        let lamp = KhalaEntity(entityId: "light.reading", state: "on", lastChanged: KhalaTestFixtures.now,
                               attributes: ["friendly_name": "Reading"], deviceId: "dev-r", deviceName: "Reading",
                               translationKey: nil, areaId: "area_study", labels: ["khala_kind_light"])
        let plug = KhalaEntity(entityId: "switch.kettle", state: "off", lastChanged: KhalaTestFixtures.now,
                               attributes: [:], deviceId: "dev-k", deviceName: "Kettle", areaId: "area_kitchen")
        #expect(KhalaTestFixtures.home[0].areaId == nil)
        #expect(KhalaTestFixtures.home[0].labels.isEmpty)
        #expect(KhalaTestFixtures.home[0].translationKey == nil)
        let detected = KhalaDeviceCatalog.build(entities: [lamp, plug], assignments: [])
        // Slice 3 applies the `khala:kind:light` label: the lamp is detected too, after the plug.
        #expect(detected.map(\.areaId) == ["area_kitchen", "area_study"])
        #expect(detected.map(\.kind) == [.switch, .light])
        let pinned = KhalaDeviceCatalog.build(
            entities: [lamp, plug],
            assignments: [KhalaRoleAssignment(entityId: "light.reading", kind: .light, label: nil)]
        )
        #expect(pinned.first?.areaId == "area_study")
        #expect(pinned.first?.kind == .light)
        #expect(pinned.first?.category == .sun)
    }

    @Test func aLegacyDeviceInitialiserPicksTheRolesKind() {
        let device = KhalaDevice(id: "b", name: "Hot water", category: .heat, primaryEntityId: "switch.b",
                                 stateText: "Off", memberEntityIds: [], isPinned: true)
        #expect(device.kind == .waterHeater)
        #expect(device.category == .heat)
        let door = KhalaDevice(id: "d", name: "Door", category: .security, primaryEntityId: "lock.d",
                               stateText: "Locked", memberEntityIds: [], isPinned: true)
        #expect(door.kind == .lock)
        #expect(door.areaId == nil)
    }
}
