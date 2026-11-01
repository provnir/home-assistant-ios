import Foundation
@testable import HomeAssistant
import Testing

/// Slice 3: lights, light groups, fans and switches detected through descriptors, group members folded into their
/// group, and Home Assistant label overrides (`khala:hide`, `khala:kind:<kind>`) applied. Synthetic fixtures only.
struct KhalaLightFanDetectionTests {
    private typealias Kinds = KhalaKindFixtures
    private typealias Home = KhalaTestFixtures

    private static func entity(
        _ id: String,
        _ state: String,
        _ attributes: [String: Any] = [:],
        device: String? = nil,
        translationKey: String? = nil,
        area: String? = nil,
        labels: [String] = []
    ) -> KhalaEntity {
        KhalaEntity(entityId: id, state: state, lastChanged: Home.now, attributes: attributes, deviceId: device,
                    deviceName: device.map { _ in "Gadget" }, translationKey: translationKey, areaId: area,
                    labels: labels)
    }

    private static func ids(_ devices: [KhalaDevice]) -> [String] { devices.map(\.primaryEntityId) }

    @Test func lightsFansAndSwitchesAreDetected() {
        let devices = KhalaDeviceCatalog.build(entities: Kinds.all, assignments: [])
        let byFace = Dictionary(devices.map { ($0.primaryEntityId, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(byFace["light.desk_lamp"]?.kind == .light)
        #expect(byFace["light.hall_bulb"]?.kind == .light)
        #expect(byFace["light.lounge_lights"]?.kind == .lightGroup)
        #expect(byFace["fan.attic_fan"]?.kind == .fan)
        #expect(byFace["switch.desk_plug"]?.kind == .switch)
        // Lights borrow the sun accent, the fan the neutral one (decision 3).
        #expect(byFace["light.desk_lamp"]?.accent == .sun)
        #expect(byFace["fan.attic_fan"]?.accent == .neutral)
        // Vacuums wait for their slice (covers, locks and climate: `KhalaClimateCoverLockTests`).
        #expect(byFace["vacuum.dust_bot"] == nil)
    }

    @Test func groupMembersFoldIntoTheirGroup() {
        let devices = KhalaDeviceCatalog.build(entities: Kinds.all, assignments: [])
        for member in Kinds.loungeMembers {
            #expect(!Self.ids(devices).contains(member.entityId), "\(member.entityId)")
        }
        #expect(Kinds.loungeGroup.groupMembers == Kinds.loungeMembers.map(\.entityId))
        // Without the group (hidden from Khala) its members are listed on their own again.
        let hiddenGroup = Self.entity("light.lounge_lights", "on", Kinds.attributes["light.lounge_lights"] ?? [:],
                                      labels: ["khala_hide"])
        let entities = Kinds.all.filter { $0.entityId != "light.lounge_lights" } + [hiddenGroup]
        let unfolded = KhalaDeviceCatalog.build(entities: entities, assignments: [])
        #expect(!Self.ids(unfolded).contains("light.lounge_lights"))
        for member in Kinds.loungeMembers {
            #expect(Self.ids(unfolded).contains(member.entityId), "\(member.entityId)")
        }
    }

    @Test func aLightBeatsASwitchOnTheSameDevice() {
        let light = Self.entity("light.combo", "on", ["supported_color_modes": ["brightness"]], device: "dev-combo")
        let relay = Self.entity("switch.combo_child_lock", "off", device: "dev-combo", translationKey: "child_lock")
        let devices = KhalaDeviceCatalog.build(entities: [relay, light], assignments: [])
        #expect(devices.count == 1)
        #expect(devices.first?.kind == .light)
        #expect(devices.first?.primaryEntityId == "light.combo")
        #expect(devices.first?.memberEntityIds == ["switch.combo_child_lock", "light.combo"])
    }

    @Test func aFanBeatsItsLight() {
        let fan = Self.entity("fan.ceiling", "off", ["supported_features": 1], device: "dev-ceiling")
        let light = Self.entity("light.ceiling_light", "on", device: "dev-ceiling", translationKey: "light")
        let devices = KhalaDeviceCatalog.build(entities: [light, fan], assignments: [])
        #expect(devices.map(\.kind) == [.fan])
        #expect(devices.first?.primaryEntityId == "fan.ceiling")
    }

    @Test func theMainEntityWinsATieThenTheLowestId() {
        let night = Self.entity("switch.a_night_mode", "off", device: "dev-p", translationKey: "night_mode")
        let main = Self.entity("switch.z_plug", "on", device: "dev-p")
        let other = Self.entity("switch.b_led", "on", device: "dev-p", translationKey: "led")
        #expect(KhalaDeviceCatalog.build(entities: [night, main, other], assignments: [])
            .first?.primaryEntityId == "switch.z_plug")
        let devices = KhalaDeviceCatalog.build(entities: [other, night], assignments: [])
        #expect(devices.first?.primaryEntityId == "switch.a_night_mode")
    }

    @Test func aLightOnADeviceDetectionDoesNotCoverYetStaysAFeature() {
        let robot = Self.entity("vacuum.robot", "docked", device: "dev-robot")
        let lamp = Self.entity("light.robot_lamp", "off", device: "dev-robot", translationKey: "light")
        #expect(KhalaDeviceCatalog.build(entities: [robot, lamp], assignments: []).isEmpty)
    }

    @Test func helpersStayOffTheMenu() {
        let helper = Self.entity("input_boolean.guest_mode", "on")
        #expect(KhalaDescriptors.shown(for: helper).kind == .switch)
        #expect(KhalaDeviceCatalog.build(entities: [helper], assignments: []).isEmpty)
    }

    @Test func groupsAreKnownWithoutRawAttributes() {
        let group = Self.entity("light.hall_group", "on", ["entity_id": ["light.a", "light.b"]])
        #expect(group.groupMembers == ["light.a", "light.b"])
        #expect(KhalaDescriptors.shown(for: group).kind == .lightGroup)
        #expect(KhalaDescriptors.shown(for: group, attributes: [:]).kind == .lightGroup)
        #expect(KhalaDescriptors.shown(for: Kinds.deskLamp).kind == .light)
        #expect(KhalaDescriptors.shown(for: group).template == .light)
        #expect(KhalaDescriptors.shown(for: Kinds.atticFan).template == .fan)
        #expect(KhalaDescriptors.shown(for: Kinds.deskPlug).template == .generic)
    }

    // MARK: - Label overrides

    @Test func khalaHideKeepsAnEntityOutOfKhala() {
        let lamp = Self.entity("light.attic", "on", device: "dev-attic", labels: ["khala_hide"])
        let plug = Self.entity("switch.attic_plug", "on", device: "dev-attic-plug", labels: ["khala:hide"])
        let camera = Self.entity("camera.shed", "idle", labels: ["khala_hide"])
        let entities = [lamp, plug, camera, Kinds.deskLamp]
        #expect(Self.ids(KhalaDeviceCatalog.build(entities: entities, assignments: [])) == ["light.desk_lamp"])
        #expect(KhalaDeviceCatalog.cameras(in: entities).isEmpty)
        // A hidden face hands the device to the next member.
        let relay = Self.entity("switch.attic_relay", "off", device: "dev-attic", translationKey: "relay")
        let devices = KhalaDeviceCatalog.build(entities: [lamp, relay], assignments: [])
        #expect(devices.map(\.primaryEntityId) == ["switch.attic_relay"])
        #expect(devices.first?.memberEntityIds == ["switch.attic_relay"])
    }

    @Test func khalaHideKeepsAnEntityOffToday() {
        let detection = Home.home.first { $0.entityId == "event.porch_field_detection" }!
        let hidden = KhalaEntity(entityId: detection.entityId, state: detection.state,
                                 lastChanged: detection.lastChanged,
                                 attributes: ["device_class": detection.deviceClass ?? "",
                                              "friendly_name": detection.name, "event_type": detection.eventType ?? ""],
                                 deviceId: detection.deviceId, deviceName: detection.deviceName,
                                 labels: ["khala_hide"])
        func items(_ entities: [KhalaEntity]) -> [String] {
            KhalaTimeline.build(entities: entities, devices: [], automationConfigs: [:], now: Home.now,
                                calendar: Home.calendar).items.map(\.id)
        }
        let shown = items(Home.home)
        let withHidden = items(Home.home.map { $0.entityId == detection.entityId ? hidden : $0 })
        #expect(shown.contains { $0.contains(detection.entityId) })
        #expect(!withHidden.contains { $0.contains(detection.entityId) })
    }

    @Test func aKindLabelBeatsTheTable() {
        // A relay wired to a lamp: shown as a light, on the light screen.
        let relay = Self.entity("switch.lamp_relay", "on", device: "dev-relay", labels: ["khala_kind_light"])
        let devices = KhalaDeviceCatalog.build(entities: [relay], assignments: [])
        #expect(devices.map(\.kind) == [.light])
        #expect(devices.first?.accent == .sun)
        #expect(KhalaDescriptors.shown(for: relay).template == .light)
        // A labelled member beats a higher-priority built-in face, even on a device detection doesn't cover.
        let cover = Self.entity("cover.blind", "open", device: "dev-blind")
        let motor = Self.entity("switch.blind_motor", "on", device: "dev-blind", labels: ["khala:kind:switch"])
        #expect(KhalaDeviceCatalog.build(entities: [cover, motor], assignments: []).map(\.primaryEntityId)
            == ["switch.blind_motor"])
        // An unknown kind, or a suffixed id HA gives a duplicate label, changes nothing.
        let odd = Self.entity("switch.odd", "on", labels: ["khala_kind_spaceship", "khala_hide_2"])
        #expect(KhalaDeviceCatalog.build(entities: [odd], assignments: []).map(\.kind) == [.switch])
    }

    @Test func aPinBeatsTheLabels() {
        let lamp = Self.entity("light.porch", "on", device: "dev-porch", labels: ["khala_hide"])
        let devices = KhalaDeviceCatalog.build(
            entities: [lamp],
            assignments: [KhalaRoleAssignment(entityId: "light.porch", kind: .light, label: nil)]
        )
        #expect(devices.map(\.id) == ["pin:light.porch"])
        // A pinned group still folds its members.
        let pinned = KhalaDeviceCatalog.build(
            entities: Kinds.all,
            assignments: [KhalaRoleAssignment(entityId: "light.lounge_lights", role: .neutral, label: nil)]
        )
        for member in Kinds.loungeMembers {
            #expect(!Self.ids(pinned).contains(member.entityId), "\(member.entityId)")
        }
    }

    @Test func detectedLightsRouteToTheirScreen() {
        let devices = KhalaDeviceCatalog.build(entities: Kinds.all, assignments: [])
        func route(_ id: String) -> String {
            KhalaGolden.route(KhalaRouting.target(forEntityId: id, entities: Kinds.all, devices: devices,
                                                  automationConfigs: [:]))
        }
        #expect(route("light.desk_lamp") == "screen device(dev-lamp)")
        #expect(route("light.lounge_lights") == "screen device(entity:light.lounge_lights)")
        // A folded member opens its own (light) screen.
        #expect(route("light.lounge_floor") == "screen entity(light.lounge_floor)")
        #expect(route("fan.attic_fan") == "screen device(dev-fan)")
    }
}
