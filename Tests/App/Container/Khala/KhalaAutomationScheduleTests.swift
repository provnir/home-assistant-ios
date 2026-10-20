import Foundation
@testable import HomeAssistant
import Testing

struct KhalaAutomationScheduleTests {
    private typealias Fixtures = KhalaTestFixtures

    private var entities: [String: KhalaEntity] {
        Dictionary(Fixtures.home.map { ($0.entityId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var horizon: Date { Fixtures.date("2026-10-21T01:00:00+03:00") }

    private func times(_ config: [String: Any], horizon: Date? = nil) -> [String] {
        KhalaAutomationSchedule.fireDates(
            config: config,
            entities: entities,
            now: Fixtures.now,
            horizon: horizon ?? self.horizon,
            calendar: Fixtures.calendar
        ).map { KhalaText.time($0, calendar: Fixtures.calendar) }
    }

    @Test func literalTimesInBothSpellings() {
        #expect(times(Fixtures.midnightCheckConfig) == ["00:00"])
        #expect(times(Fixtures.eveningLightsConfig) == ["20:00"])
    }

    @Test func pastTimesTodayWaitForTomorrow() {
        let config: [String: Any] = ["triggers": [["trigger": "time", "at": "06:30"]]]
        #expect(times(config).isEmpty)
        let longer = Fixtures.date("2026-10-21T08:00:00+03:00")
        #expect(times(config, horizon: longer) == ["06:30"])
    }

    @Test func listsOfTimesAndHelpers() {
        let config: [String: Any] = ["triggers": [["trigger": "time", "at": ["13:15", "input_datetime.wake_up", "{{ x }}"]]]]
        let longer = Fixtures.date("2026-10-21T08:00:00+03:00")
        #expect(times(config, horizon: longer) == ["13:15", "06:30"])
    }

    @Test func timestampSensorWithOffset() {
        let config: [String: Any] = ["triggers": [[
            "trigger": "time",
            "at": ["entity_id": "sensor.rover_time_to_full_charge", "offset": "-00:30:00"],
        ]]]
        #expect(times(config) == ["19:00"])
    }

    @Test func weekdayFilter() {
        // 2026-10-20 is a Tuesday.
        let tuesday: [String: Any] = ["triggers": [["trigger": "time", "at": "15:00", "weekday": "tue"]]]
        let weekend: [String: Any] = ["triggers": [["trigger": "time", "at": "15:00", "weekday": ["sat", "sun"]]]]
        #expect(times(tuesday) == ["15:00"])
        #expect(times(weekend).isEmpty)
    }

    @Test func sunTriggersWithOffsets() {
        let config: [String: Any] = ["triggers": [
            ["trigger": "sun", "event": "sunset", "offset": "-00:15:00"],
            ["platform": "sun", "event": "sunrise", "offset": 3600],
        ]]
        #expect(times(config) == ["17:47"])
    }

    @Test func disabledAndUnknownTriggersAreSkipped() {
        let config: [String: Any] = ["triggers": [
            ["trigger": "time", "at": "15:00", "enabled": false],
            ["trigger": "state", "entity_id": "switch.relay_7"],
            ["trigger": "time_pattern", "minutes": "/5"],
        ]]
        #expect(times(config).isEmpty)
    }

    @Test func referencedEntitiesSkipServiceNames() {
        let ids = KhalaAutomationSchedule.referencedEntityIds(config: Fixtures.midnightCheckConfig, entities: entities)
        #expect(ids == ["switch.relay_7"])
        let legacy = KhalaAutomationSchedule.referencedEntityIds(config: Fixtures.eveningLightsConfig, entities: entities)
        #expect(legacy == ["switch.relay_7"])
    }
}
