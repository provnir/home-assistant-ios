import Foundation
@testable import HomeAssistant

/// Synthetic home for the Khala model tests: no real entity ids or names. "Now" is 2026-10-20 12:00 at UTC+3.
enum KhalaTestFixtures {
    static let zone = TimeZone(secondsFromGMT: 3 * 3600)!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    static func date(_ string: String) -> Date {
        KhalaDateParser.timestamp(string)!
    }

    static let now = date("2026-10-20T12:00:00+03:00")

    static func entity(
        _ entityId: String,
        _ state: String,
        _ attributes: [String: Any] = [:],
        device: String? = nil,
        deviceName: String? = nil,
        auxiliary: Bool = false
    ) -> KhalaEntity {
        KhalaEntity(
            entityId: entityId,
            state: state,
            lastChanged: now.addingTimeInterval(-3600),
            attributes: attributes,
            deviceId: device,
            deviceName: deviceName,
            isAuxiliary: auxiliary
        )
    }

    /// A small home: sun, weather, two cameras with detection events, a car, a receiver, a speaker, a relay,
    /// a phone, a timestamp sensor and two automations.
    static var home: [KhalaEntity] {
        [
            entity("sun.sun", "above_horizon", [
                "next_rising": "2026-10-21T03:48:30.681916+00:00",
                "next_setting": "2026-10-20T15:02:16.933537+00:00",
                "friendly_name": "Sun",
            ]),
            entity("weather.home", "sunny", ["temperature": 21.4, "friendly_name": "Home"]),

            entity("camera.porch", "idle", ["friendly_name": "Porch"], device: "dev-porch", deviceName: "Porch"),
            entity("event.porch_field_detection", "2026-10-20T07:35:02.953+00:00", [
                "event_type": "human", "device_class": "motion", "friendly_name": "Porch Field detection",
            ], device: "dev-porch", deviceName: "Porch"),
            entity("event.porch_line_crossing", "unknown", [
                "event_type": NSNull(), "device_class": "motion", "friendly_name": "Porch Line crossing",
            ], device: "dev-porch", deviceName: "Porch"),
            entity("camera.yard", "idle", ["friendly_name": "Yard"], device: "dev-yard", deviceName: "Yard"),
            entity("event.yard_field_detection", "2026-10-19T18:00:50.077+00:00", [
                "event_type": "human", "device_class": "motion", "friendly_name": "Yard Field detection",
            ], device: "dev-yard", deviceName: "Yard"),

            entity("device_tracker.rover_location", "not_home", ["source_type": "gps", "friendly_name": "Rover Location"],
                   device: "dev-rover", deviceName: "Rover"),
            entity("lock.rover_lock", "locked", ["friendly_name": "Rover Lock"], device: "dev-rover", deviceName: "Rover"),
            entity("sensor.rover_battery_level", "72", [
                "device_class": "battery", "unit_of_measurement": "%", "friendly_name": "Rover Battery level",
            ], device: "dev-rover", deviceName: "Rover"),
            entity("switch.rover_defrost", "off", ["friendly_name": "Rover Defrost"], device: "dev-rover", deviceName: "Rover"),
            entity("media_player.rover_media", "paused", ["device_class": "speaker", "friendly_name": "Rover Media"],
                   device: "dev-rover", deviceName: "Rover"),
            entity("sensor.rover_time_to_full_charge", "2026-10-20T16:30:00+00:00", [
                "device_class": "timestamp", "friendly_name": "Rover Time to full charge",
            ], device: "dev-rover", deviceName: "Rover"),

            entity("media_player.den_zone_2", "off", ["friendly_name": "Den Zone 2"], device: "dev-den", deviceName: "Den"),
            entity("media_player.den_receiver", "off", ["device_class": "receiver", "friendly_name": "Den Receiver"],
                   device: "dev-den", deviceName: "Den"),
            entity("media_player.kitchen_speaker", "playing", ["device_class": "speaker", "friendly_name": "Kitchen"],
                   device: "dev-kitchen", deviceName: "Kitchen speaker"),

            entity("switch.relay_7", "off", ["device_class": "switch", "friendly_name": "Relay 7"],
                   device: "dev-relay", deviceName: "Relay 7"),
            entity("sensor.relay_7_power", "0", ["device_class": "power", "unit_of_measurement": "W"],
                   device: "dev-relay", deviceName: "Relay 7"),

            entity("device_tracker.phone", "home", ["source_type": "gps", "friendly_name": "Phone"],
                   device: "dev-phone", deviceName: "Phone"),
            entity("sensor.phone_battery_level", "65", ["device_class": "battery", "unit_of_measurement": "%"],
                   device: "dev-phone", deviceName: "Phone"),

            entity("automation.midnight_check", "on", ["friendly_name": "Midnight check"]),
            entity("automation.evening_lights", "off", ["friendly_name": "Evening lights"]),
            entity("input_datetime.wake_up", "06:30:00", [
                "has_date": false, "has_time": true, "hour": 6, "minute": 30, "second": 0,
            ]),
        ]
    }

    static let midnightCheckConfig: [String: Any] = [
        "id": "midnight_check",
        "alias": "Midnight check",
        "triggers": [["trigger": "time", "at": "00:00:00"]],
        "actions": [[
            "action": "switch.turn_on",
            "target": ["entity_id": "switch.relay_7"],
        ]],
    ]

    static let eveningLightsConfig: [String: Any] = [
        "trigger": [["platform": "time", "at": "20:00"]],
        "action": [["service": "switch.turn_on", "entity_id": "switch.relay_7"]],
    ]
}
