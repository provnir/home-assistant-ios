import Foundation
@testable import HomeAssistant
import Testing

struct KhalaCameraCatalogTests {
    private typealias Fixtures = KhalaTestFixtures

    private var porch: KhalaEntity { Fixtures.home.first { $0.entityId == "camera.porch" }! }

    @Test func eventsBelongToTheCamerasDevice() {
        let events = KhalaCameraCatalog.eventEntities(for: porch, in: Fixtures.home).map(\.entityId)
        #expect(events == ["event.porch_field_detection", "event.porch_line_crossing"])
    }

    @Test func eventsMatchByNameWithoutRegistry() {
        let camera = KhalaScreenFixtures.entity("camera.gate", "idle", ["friendly_name": "Gate"])
        let entities = [
            camera,
            KhalaScreenFixtures.entity("event.gate_person", "2026-10-20T08:00:00+00:00",
                                       ["friendly_name": "Gate Person", "device_class": "motion", "event_type": "person"]),
            KhalaScreenFixtures.entity("event.gatehouse_bell", "unknown", ["friendly_name": "Gatehouse Bell"]),
        ]
        let detections = KhalaCameraCatalog.detections(
            for: camera, in: entities, since: Fixtures.calendar.startOfDay(for: Fixtures.now), now: Fixtures.now
        )
        #expect(detections.map(\.source) == ["Person"])
        #expect(detections.map(\.noun) == ["Person"])
    }

    @Test func historyAddsEarlierDetectionsWithoutDuplicates() {
        let history = KhalaHistory.parse([
            "event.porch_field_detection": [
                ["s": "2026-10-20T04:10:00.000+00:00", "a": ["event_type": "vehicle"], "lu": 1_792_469_400.5],
                ["s": "2026-10-20T07:35:02.953+00:00", "a": ["event_type": "human"], "lu": 1_792_481_703.0],
                ["s": "2026-10-18T07:35:02.953+00:00", "lu": 1_792_300_000.0],
            ],
        ])
        let detections = KhalaCameraCatalog.detections(
            for: porch, in: Fixtures.home, history: history,
            since: Fixtures.calendar.startOfDay(for: Fixtures.now), now: Fixtures.now
        )
        #expect(detections.map(\.noun) == ["Person", "Vehicle"])
        #expect(detections.map(\.source) == ["Field detection", "Field detection"])
    }

    @Test func pickerRowsSayWhatWasSeenOrClear() {
        let cameras = KhalaDeviceCatalog.cameras(in: Fixtures.home)
        let rows = KhalaCameraCatalog.rows(cameras: cameras, entities: Fixtures.home, now: Fixtures.now,
                                           calendar: Fixtures.calendar)
        #expect(rows.map(\.stateText) == ["Person 10:35", "Clear"])
        #expect(rows.map(\.hasDetectionToday) == [true, false])
    }

    @Test func muteNeedsANotificationSwitch() {
        #expect(KhalaCameraCatalog.notificationSwitch(for: porch, in: Fixtures.home) == nil)
        let entities = Fixtures.home + [
            KhalaScreenFixtures.entity("switch.porch_push_notifications", "on", ["friendly_name": "Porch Push notifications"],
                                       device: "dev-porch", deviceName: "Porch"),
        ]
        #expect(KhalaCameraCatalog.notificationSwitch(for: porch, in: entities)?.entityId == "switch.porch_push_notifications")
        #expect(KhalaCameraCatalog.supportsStream(attributes: ["supported_features": 2]))
        #expect(!KhalaCameraCatalog.supportsStream(attributes: [:]))
    }
}

struct KhalaHistoryTests {
    private func state(_ value: String, _ minutes: Double) -> KhalaHistoryState {
        KhalaHistoryState(state: value, date: KhalaTestFixtures.now.addingTimeInterval(minutes * 60), eventType: nil)
    }

    @Test func runsPairOnWithOff() {
        let runs = KhalaHistory.runs([
            state("off", -300), state("on", -270), state("off", -225), state("unavailable", -100),
            state("on", -20),
        ], now: KhalaTestFixtures.now)
        #expect(runs.count == 2)
        #expect(runs[0].end == nil)
        #expect(runs[0].duration(now: KhalaTestFixtures.now) == 1200)
        #expect(runs[1].duration(now: KhalaTestFixtures.now) == 45 * 60)
    }

    @Test func presenceIgnoresNoiseAndUnknowns() {
        let changes = KhalaHistory.presenceChanges([
            state("home", -900), state("not_home", -600), state("not_home", -590), state("unknown", -400),
            state("home", -60),
        ])
        #expect(changes.map(\.arrived) == [true, false])
        #expect(changes.map(\.place) == ["home", "home"])
    }

    @Test func parseSkipsBrokenRowsAndSorts() {
        let parsed = KhalaHistory.parse(["switch.a": [
            ["s": "on", "lu": 20.0], ["s": "off", "lu": 10], ["lu": 5.0], "junk",
        ]])
        #expect(parsed["switch.a"]?.map(\.state) == ["off", "on"])
    }
}

struct KhalaRoutingTests {
    private typealias Fixtures = KhalaTestFixtures

    private var devices: [KhalaDevice] {
        KhalaDeviceCatalog.build(entities: Fixtures.home, assignments: [])
    }

    private func target(_ entityId: String, configs: [String: [String: Any]] = [:]) -> KhalaRouteTarget {
        KhalaRouting.target(forEntityId: entityId, entities: Fixtures.home, devices: devices, automationConfigs: configs)
    }

    @Test func everyTapLandsOnANativeScreen() {
        #expect(target("camera.yard") == .screen(.camera(entityId: "camera.yard")))
        #expect(target("event.porch_field_detection") == .screen(.camera(entityId: "camera.porch")))
        #expect(target("sensor.rover_battery_level") == .screen(.device(id: "dev-rover")))
        #expect(target("sensor.rover_time_to_full_charge") == .screen(.device(id: "dev-rover")))
        #expect(target("media_player.den_receiver") == .mediaSheet(deviceId: "dev-den"))
        #expect(target("switch.relay_7") == .screen(.device(id: "dev-relay")))
        #expect(target("weather.home") == .screen(.entity(entityId: "weather.home")))
    }

    @Test func automationsOpenTheDeviceTheyRun() {
        #expect(target("automation.midnight_check", configs: ["automation.midnight_check": Fixtures.midnightCheckConfig])
            == .screen(.device(id: "dev-relay")))
        #expect(target("automation.evening_lights") == .screen(.automations))
    }

    @Test func pinnedHeatSwitchOpensItsDeviceScreen() {
        let pinned = KhalaDeviceCatalog.build(
            entities: Fixtures.home,
            assignments: [KhalaRoleAssignment(entityId: "switch.relay_7", role: .heat, label: "Hot water")]
        )
        let route = KhalaRouting.target(forEntityId: "switch.relay_7", entities: Fixtures.home, devices: pinned,
                                        automationConfigs: [:])
        #expect(route == .screen(.device(id: "pin:switch.relay_7")))
    }

    @Test func destinationsKnowTheirMenuRow() {
        #expect(KhalaDestination.allCases == [.today, .cameras, .automations, .dashboards])
        #expect(KhalaDestination.camera(entityId: "camera.a").menuHighlight == .cameras)
        #expect(KhalaDestination.device(id: "x").menuHighlight == nil)
        #expect(!KhalaDestination.entity(entityId: "x").isMenuDestination)
        #expect(KhalaDestination.today.isMenuDestination)
    }
}
