import Foundation
@testable import HomeAssistant

/// Synthetic devices for the device-screen tests, shaped like real integrations (a Tesla Fleet car, a Denon-style
/// receiver, a Switcher water heater, cameras with event entities) but with made-up ids and names. The car and the
/// heater carry the registry facts those integrations give their entities (platform, translation key), which is
/// what the hints file reads.
enum KhalaScreenFixtures {
    private typealias Base = KhalaTestFixtures

    static func entity(_ id: String, _ state: String, _ attributes: [String: Any] = [:], device: String? = nil,
                       deviceName: String? = nil, auxiliary: Bool = false, platform: String? = nil,
                       translationKey: String? = nil) -> KhalaEntity {
        Base.entity(id, state, attributes, device: device, deviceName: deviceName, auxiliary: auxiliary,
                    platform: platform, translationKey: translationKey)
    }

    /// The registry's `translation_key` of each synthetic car entity: the keys Home Assistant's `tesla_fleet`
    /// integration gives these entities (what the hints file is keyed on; the update entity has none).
    static let carTranslationKeys: [String: String] = [
        "device_tracker.rover_location": "location",
        "device_tracker.rover_route": "route",
        "lock.rover_lock": "vehicle_state_locked",
        "lock.rover_charge_cable_lock": "charge_state_charge_port_latch",
        "sensor.rover_battery_level": "charge_state_battery_level",
        "sensor.rover_battery_range": "charge_state_battery_range",
        "sensor.rover_charging": "charge_state_charging_state",
        "sensor.rover_charger_power": "charge_state_charger_power",
        "sensor.rover_inside_temperature": "climate_state_inside_temp",
        "sensor.rover_outside_temperature": "climate_state_outside_temp",
        "number.rover_charge_limit": "charge_state_charge_limit_soc",
        "number.rover_charge_current": "charge_state_charge_current_request",
        "binary_sensor.rover_status": "state",
        "binary_sensor.rover_charge_cable": "charge_state_conn_charge_cable",
        "climate.rover_climate": "driver_temp",
        "switch.rover_sentry_mode": "vehicle_state_sentry_mode",
        "switch.rover_defrost": "climate_state_defrost_mode",
        "switch.rover_charge": "charge_state_charging_state",
        "switch.rover_auto_seat_climate_left": "climate_state_auto_seat_climate_left",
        "cover.rover_charge_port_door": "charge_state_charge_port_door_open",
        "cover.rover_frunk": "vehicle_state_ft",
        "cover.rover_trunk": "vehicle_state_rt",
        "button.rover_wake": "wake",
        "button.rover_flash_lights": "flash_lights",
        "button.rover_honk_horn": "honk",
        "button.rover_homelink": "homelink",
        "button.rover_play_sound": "boombox",
        "media_player.rover_media_player": "media",
        "select.rover_seat_heater_front_left": "climate_state_seat_heater_left",
    ]

    // MARK: - Car

    static let carAttributes: [String: [String: Any]] = [
        "climate.rover_climate": [
            "hvac_modes": ["heat_cool", "off"], "min_temp": 15.0, "max_temp": 28.0, "temperature": 21.0,
            "current_temperature": 27.5, "friendly_name": "Rover Climate",
        ],
        "number.rover_charge_limit": ["min": 50, "max": 100, "step": 1, "device_class": "battery",
                                      "unit_of_measurement": "%"],
        "number.rover_charge_current": ["min": 0, "max": 16, "step": 1, "device_class": "current",
                                        "unit_of_measurement": "A"],
        "cover.rover_frunk": ["supported_features": 1],
        "cover.rover_trunk": ["supported_features": 3],
        "cover.rover_charge_port_door": ["supported_features": 3],
        "select.rover_seat_heater_front_left": ["options": ["off", "low", "medium", "high"]],
    ]

    static var car: [KhalaEntity] {
        func car(_ id: String, _ state: String, _ attributes: [String: Any] = [:], auxiliary: Bool = false) -> KhalaEntity {
            var merged = carAttributes[id] ?? [:]
            for (key, value) in attributes { merged[key] = value }
            return entity(id, state, merged, device: "dev-rover", deviceName: "Rover", auxiliary: auxiliary,
                          platform: "tesla_fleet", translationKey: carTranslationKeys[id])
        }
        return [
            car("device_tracker.rover_location", "home", ["friendly_name": "Rover Location"]),
            car("device_tracker.rover_route", "not_home", ["friendly_name": "Rover Route"]),
            car("lock.rover_lock", "locked", ["friendly_name": "Rover Lock"]),
            car("lock.rover_charge_cable_lock", "locked", ["friendly_name": "Rover Charge cable lock"]),
            car("sensor.rover_battery_level", "65", ["device_class": "battery", "unit_of_measurement": "%",
                                                     "friendly_name": "Rover Battery level"]),
            car("sensor.rover_battery_range", "301.57", ["device_class": "distance", "unit_of_measurement": "km",
                                                         "friendly_name": "Rover Battery range"]),
            car("sensor.rover_charging", "disconnected", ["device_class": "enum", "friendly_name": "Rover Charging"]),
            car("sensor.rover_charger_power", "0", ["device_class": "power", "unit_of_measurement": "kW",
                                                    "friendly_name": "Rover Charger power"]),
            car("sensor.rover_inside_temperature", "27.4", ["device_class": "temperature",
                                                            "friendly_name": "Rover Inside temperature"]),
            car("sensor.rover_outside_temperature", "26.5", ["device_class": "temperature",
                                                             "friendly_name": "Rover Outside temperature"]),
            car("number.rover_charge_limit", "80", ["friendly_name": "Rover Charge limit"]),
            car("number.rover_charge_current", "16", ["friendly_name": "Rover Charge current"]),
            car("binary_sensor.rover_status", "off", ["device_class": "connectivity", "friendly_name": "Rover Status"]),
            car("binary_sensor.rover_charge_cable", "off", ["device_class": "connectivity",
                                                            "friendly_name": "Rover Charge cable"]),
            car("climate.rover_climate", "off"),
            car("switch.rover_sentry_mode", "on", ["friendly_name": "Rover Sentry mode"]),
            car("switch.rover_defrost", "off", ["friendly_name": "Rover Defrost"]),
            car("switch.rover_charge", "off", ["friendly_name": "Rover Charge"]),
            car("switch.rover_auto_seat_climate_left", "off", ["friendly_name": "Rover Auto seat climate left"]),
            car("cover.rover_charge_port_door", "closed", ["device_class": "door", "friendly_name": "Rover Charge port door"]),
            car("cover.rover_frunk", "closed", ["device_class": "door", "friendly_name": "Rover Frunk"]),
            car("cover.rover_trunk", "closed", ["device_class": "door", "friendly_name": "Rover Trunk"]),
            car("button.rover_wake", "unknown", ["friendly_name": "Rover Wake"]),
            car("button.rover_flash_lights", "unknown", ["friendly_name": "Rover Flash lights"]),
            car("button.rover_honk_horn", "unknown", ["friendly_name": "Rover Honk horn"]),
            car("button.rover_homelink", "unknown", ["friendly_name": "Rover Homelink"]),
            car("button.rover_play_sound", "unknown", ["friendly_name": "Rover Play sound"]),
            car("media_player.rover_media_player", "paused", ["device_class": "speaker", "friendly_name": "Rover Media player",
                                                              "supported_features": 16437, "volume_level": 0.25]),
            car("select.rover_seat_heater_front_left", "off", ["friendly_name": "Rover Seat heater front left"]),
            car("update.rover_update", "off", ["friendly_name": "Rover Update"], auxiliary: true),
        ]
    }

    // MARK: - Heat

    static var heater: [KhalaEntity] {
        [
            entity("switch.tank_9", "on", ["device_class": "switch", "friendly_name": "Tank 9"],
                   device: "dev-tank", deviceName: "Tank 9", platform: "switcher_kis"),
            entity("sensor.tank_9_remaining_time", "00:32:10", ["friendly_name": "Tank 9 Remaining time"],
                   device: "dev-tank", deviceName: "Tank 9", platform: "switcher_kis", translationKey: "remaining_time"),
            entity("sensor.tank_9_power", "2450", ["device_class": "power", "unit_of_measurement": "W"],
                   device: "dev-tank", deviceName: "Tank 9", platform: "switcher_kis"),
            entity("input_boolean.backup_booked", "off", ["friendly_name": "Backup booked"]),
            entity("automation.backup_check", "on", ["friendly_name": "Backup check"]),
            entity("automation.backup_heat", "off", ["friendly_name": "Backup heat"]),
            entity("automation.unrelated", "on", ["friendly_name": "Unrelated"]),
            entity("switch.other", "off", ["friendly_name": "Other"]),
        ]
    }

    /// A midnight check that books a run through a helper, and the morning run that reads it and heats 45 minutes.
    static let heatConfigs: [String: [String: Any]] = [
        "automation.backup_check": [
            "alias": "Backup check",
            "description": "Books the morning run when it looks cloudy.",
            "triggers": [["trigger": "time", "at": "00:00:00"]],
            "actions": [
                ["action": "input_boolean.turn_off", "target": ["entity_id": "input_boolean.backup_booked"]],
                ["if": [["condition": "template", "value_template": "{{ true }}"]],
                 "then": [["action": "input_boolean.turn_on", "target": ["entity_id": "input_boolean.backup_booked"]]]],
            ],
        ],
        "automation.backup_heat": [
            "alias": "Backup heat",
            "triggers": [["trigger": "time", "at": "07:30:00"]],
            "conditions": [["condition": "state", "entity_id": "input_boolean.backup_booked", "state": "on"]],
            "actions": [
                ["action": "input_boolean.turn_off", "target": ["entity_id": "input_boolean.backup_booked"]],
                ["action": "switcher_kis.turn_on_with_timer", "target": ["entity_id": "switch.tank_9"],
                 "data": ["timer_minutes": 45]],
            ],
        ],
        "automation.unrelated": [
            "triggers": [["trigger": "time", "at": "20:00"]],
            "actions": [["action": "switch.turn_on", "target": ["entity_id": "switch.other"]]],
        ],
    ]

    // MARK: - Media

    static let receiver = entity("media_player.den_receiver", "on", ["device_class": "receiver"],
                                 device: "dev-den", deviceName: "Den")
    static let receiverAttributes: [String: Any] = [
        "supported_features": 69004,
        "volume_level": 0.455,
        "is_volume_muted": false,
        "source_list": ["Bluetooth", "Music", "Console"],
        "source": "Music",
        "sound_mode_list": ["MUSIC", "MOVIE", "STEREO"],
        "sound_mode": "STEREO",
    ]
}
