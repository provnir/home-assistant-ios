import Foundation
@testable import HomeAssistant
import Shared
import Testing

/// The descriptor scaffolding of slice 1: the built-in table, entity matching over the synthetic kind fixtures
/// (with Home Assistant's own capability parsers), and the kinds the catalog now carries.
struct KhalaDescriptorTests {
    private typealias Kinds = KhalaKindFixtures

    private static func kind(of entity: KhalaEntity) -> KhalaKind {
        KhalaDescriptors.descriptor(for: entity, attributes: Kinds.everythingAttributes[entity.entityId] ?? [:]).kind
    }

    @Test func theTableHasOneEntryPerKindInPriorityOrder() {
        let kinds = KhalaDescriptors.all.map(\.kind)
        #expect(Set(kinds).count == kinds.count)
        #expect(kinds == [
            .car, .waterHeater, .climate, .media, .vacuum, .lock, .cover, .fan, .lightGroup, .light, .switch, .camera,
            .generic,
        ])
        let priorities = KhalaDescriptors.all.map(\.priority)
        #expect(priorities == priorities.sorted(by: >))
        #expect(KhalaDescriptors.all.map(\.priority) == [100, 90, 80, 70, 60, 55, 50, 45, 41, 40, 10, 0, 0])
    }

    @Test func newKindsBorrowExistingColours() {
        // Decision 3 (2026-11-01): no new hues.
        let accents = Dictionary(
            KhalaDescriptors.all.map { ($0.kind, $0.accent) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(accents[.light] == .sun)
        #expect(accents[.lightGroup] == .sun)
        #expect(accents[.climate] == .heat)
        #expect(accents[.waterHeater] == .heat)
        #expect(accents[.lock] == .security)
        #expect(accents[.camera] == .security)
        #expect(accents[.car] == .car)
        #expect(accents[.media] == .media)
        for kind in [KhalaKind.cover, .fan, .vacuum, .switch, .generic] {
            #expect(accents[kind] == .neutral, "\(kind)")
        }
    }

    @Test func everyFixtureMatchesItsKind() {
        let expected: [(KhalaEntity, KhalaKind)] = [
            (Kinds.deskLamp, .light), (Kinds.hallBulb, .light), (Kinds.loungeGroup, .lightGroup),
            (Kinds.loungeMembers[0], .light), (Kinds.shedDoor, .cover), (Kinds.sideGate, .cover),
            (Kinds.blueDoor, .lock), (Kinds.blueDoorBattery, .generic), (Kinds.atticFan, .fan),
            (Kinds.studyAC, .climate), (Kinds.loftHeater, .climate), (Kinds.dustBot, .vacuum),
            (Kinds.cellarTank, .waterHeater), (Kinds.deskPlug, .switch), (Kinds.deskPlugPower, .generic),
            (KhalaScreenFixtures.receiver, .media), (KhalaScreenFixtures.heater[0], .switch),
            (KhalaTestFixtures.home.first { $0.domain == "camera" }!, .camera),
            (KhalaTestFixtures.home.first { $0.domain == "input_boolean" } ?? KhalaScreenFixtures.heater[3], .switch),
        ]
        for (entity, kind) in expected {
            #expect(Self.kind(of: entity) == kind, "\(entity.entityId)")
        }
    }

    @Test func aMoreSpecificMatchWins() {
        let classed = KhalaMatch(domains: ["cover"], deviceClasses: ["garage"])
        let keyed = KhalaMatch(domains: ["sensor"], translationKeys: ["charge_state"], requires: .entityGroup)
        #expect(KhalaMatch(domains: []).specificity == 0)
        #expect(KhalaMatch(domains: ["light"]).specificity == 1)
        #expect(classed.specificity == 2)
        #expect(keyed.specificity == 3)
        #expect(classed.matches(Kinds.shedDoor, attributes: [:]))
        #expect(!classed.matches(Kinds.sideGate, attributes: [:]))
        let sensor = KhalaEntity(entityId: "sensor.x_charge_state", state: "idle", lastChanged: KhalaTestFixtures.now,
                                 attributes: [:], translationKey: "charge_state")
        #expect(keyed.matches(sensor, attributes: ["entity_id": ["sensor.a"]]))
        #expect(!keyed.matches(sensor, attributes: [:]))
        #expect(!KhalaMatch(domains: ["sensor"], translationKeys: ["other"]).matches(sensor, attributes: [:]))
    }

    @Test func capabilitiesComeFromHomeAssistantsOwnParsers() {
        func passes(_ test: KhalaCapabilityTest, _ entity: KhalaEntity) -> Bool {
            test.passes(attributes: Kinds.attributes[entity.entityId] ?? [:])
        }
        #expect(passes(.lightBrightness, Kinds.deskLamp))
        #expect(passes(.lightColorTemp, Kinds.deskLamp))
        #expect(!passes(.lightColor, Kinds.deskLamp))
        #expect(!passes(.lightBrightness, Kinds.hallBulb))
        #expect(passes(.lightColor, Kinds.loungeMembers[2]))
        #expect(passes(.coverSetPosition, Kinds.shedDoor))
        #expect(passes(.coverStop, Kinds.shedDoor))
        #expect(!passes(.coverSetPosition, Kinds.sideGate))
        #expect(!passes(.coverStop, Kinds.sideGate))
        #expect(passes(.lockOpen, Kinds.blueDoor))
        #expect(!passes(.lockOpen, KhalaScreenFixtures.car.first { $0.domain == "lock" }!))
        #expect(passes(.fanSetSpeed, Kinds.atticFan))
        #expect(!passes(.vacuumCleanArea, Kinds.dustBot))
        #expect(passes(.entityGroup, Kinds.loungeGroup))
        #expect(!passes(.entityGroup, Kinds.deskLamp))
        // The upstream parser itself, run on Linux through the staged `Shared` module.
        let fan = FanCapabilities(attributes: Kinds.attributes["fan.attic_fan"] ?? [:])
        #expect(fan.percentageStep == 25)
        #expect(fan.speedPercentage == 50)
    }

    @Test func aCarIsATrackerWithALockOrAClimate() {
        let rule = KhalaKind.car.descriptor.deviceRule
        #expect(rule?.isMet(byDomains: Set(KhalaScreenFixtures.car.map(\.domain))) == true)
        #expect(rule?.isMet(byDomains: ["device_tracker", "sensor"]) == false)
        #expect(rule?.isMet(byDomains: ["device_tracker", "climate"]) == true)
        #expect(KhalaDeviceRule.face.isMet(byDomains: ["light"]) == false)
        #expect(KhalaKind.camera.descriptor.deviceRule == nil)
    }

    @Test func detectedDevicesCarryTheirKind() {
        let devices = KhalaDeviceCatalog.build(entities: Kinds.everything, assignments: [])
        // Slice 3: the fan and the lights join; the lounge members fold into their group. Slice 4: climate, the
        // lock and the covers join, and kinds sort by priority within a colour family (group before its lights).
        #expect(devices.map(\.kind) == [.car, .waterHeater, .climate, .climate, .media, .lock, .cover, .cover, .fan,
                                        .switch, .switch, .switch, .lightGroup, .light, .light])
        for device in devices {
            #expect(device.accent == device.kind.accent)
        }
    }

    @Test func kindsAreOpenStringsAndUnknownOnesReadAsGeneric() throws {
        #expect(try JSONEncoder().encode([KhalaKind.waterHeater]) == Data(#"["water_heater"]"#.utf8))
        let decoded = try JSONDecoder().decode([KhalaKind].self, from: Data(#"["light_group","hovercraft"]"#.utf8))
        #expect(decoded == [.lightGroup, KhalaKind(rawValue: "hovercraft")])
        #expect(decoded[1].isKnown == false)
        #expect(decoded[1].descriptor.kind == .generic)
        #expect(decoded[1].accent == .neutral)
    }
}
