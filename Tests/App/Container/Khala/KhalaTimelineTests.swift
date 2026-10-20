import Foundation
@testable import HomeAssistant
import Testing

struct KhalaTimelineTests {
    private typealias Fixtures = KhalaTestFixtures

    private func build(
        entities: [KhalaEntity] = KhalaTestFixtures.home,
        assignments: [KhalaRoleAssignment] = [],
        configs: [String: [String: Any]] = [:]
    ) -> KhalaTimeline {
        let devices = KhalaDeviceCatalog.build(entities: entities, assignments: assignments)
        return KhalaTimeline.build(
            entities: entities,
            devices: devices,
            automationConfigs: configs,
            now: Fixtures.now,
            calendar: Fixtures.calendar
        )
    }

    @Test func itemsRunFromThePastThroughNowIntoTheEvening() {
        let timeline = build(configs: ["automation.midnight_check": Fixtures.midnightCheckConfig])
        let rows = timeline.items.map { "\(KhalaText.time($0.date, calendar: Fixtures.calendar)) \($0.title)" }
        #expect(rows == [
            "06:48 Sunrise",
            "10:35 Person at Porch",
            "12:00 Now",
            "18:02 Sunset",
            "19:30 Rover Time to full charge",
            "00:00 Midnight check",
        ])
        #expect(timeline.items.prefix(2).allSatisfy { $0.isPast })
        #expect(timeline.items.suffix(3).allSatisfy { !$0.isPast && !$0.isNow })
    }

    @Test func detectionNamesThePlaceAndLinksTheCamera() throws {
        let detection = try #require(build().items.first { $0.category == .security })
        #expect(detection.title == "Person at Porch")
        #expect(detection.subtitle == "Field detection")
        #expect(detection.kind == .detection(
            eventEntityId: "event.porch_field_detection",
            cameraEntityId: "camera.porch"
        ))
        #expect(detection.targetEntityId == "camera.porch")
    }

    @Test func yesterdaysAndEmptyEventsAreLeftOut() {
        let titles = build().items.map(\.title)
        #expect(!titles.contains("Person at Yard"))
        #expect(titles.filter { $0.hasSuffix("at Porch") }.count == 1)
    }

    @Test func summaryCountsTodaysDetections() {
        #expect(build().summary == KhalaText.detections(1))
        let quiet = Fixtures.home.filter { $0.domain != "event" }
        #expect(build(entities: quiet).summary == KhalaText.allClear)
    }

    @Test func headlineHasWeatherAndTheSunsetCountdown() {
        #expect(build().headline == "21° and sunny · sunset in 6 h 2 m")
    }

    @Test func headlineFallsBackWhenNothingIsKnown() {
        #expect(build(entities: []).headline == KhalaText.rightNow)
    }

    @Test func scheduledAutomationBorrowsTheCategoryOfWhatItSwitches() throws {
        let pinned = [KhalaRoleAssignment(entityId: "switch.relay_7", role: .heat, label: "Hot water")]
        let timeline = build(assignments: pinned, configs: ["automation.midnight_check": Fixtures.midnightCheckConfig])
        let midnight = try #require(timeline.items.first { $0.title == "Midnight check" })
        #expect(midnight.category == .heat)
        #expect(midnight.subtitle == "Automation · Hot water")
        #expect(midnight.kind == .scheduled(automationEntityId: "automation.midnight_check"))
    }

    @Test func onlyListedDevicesContributeTimestamps() {
        let bookkeeping = Fixtures.entity("sensor.sun_next_dusk", "2026-10-20T15:27:32+00:00", [
            "device_class": "timestamp", "friendly_name": "Sun Next dusk",
        ], device: "dev-sun", deviceName: "Sun")
        let timeline = build(entities: Fixtures.home + [bookkeeping])
        #expect(!timeline.items.contains { $0.title == "Sun Next dusk" })
        #expect(timeline.items.contains { $0.title == "Rover Time to full charge" && $0.category == .car })
    }

    @Test func disabledAutomationsAreNotScheduled() {
        let timeline = build(configs: ["automation.evening_lights": Fixtures.eveningLightsConfig])
        #expect(!timeline.items.contains { $0.title == "Evening lights" })
    }

    @Test func nowCardChipsPreferPinsThenVariety() {
        #expect(build().chips.map(\.name) == ["Rover", "Den", "Relay 7"])
        let pinned = [KhalaRoleAssignment(entityId: "switch.relay_7", role: .heat, label: "Hot water")]
        #expect(build(assignments: pinned).chips.map(\.name) == ["Hot water", "Rover", "Den"])
    }
}
