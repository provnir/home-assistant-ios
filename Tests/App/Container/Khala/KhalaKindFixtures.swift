import Foundation
@testable import HomeAssistant

/// Synthetic devices of every kind the descriptor design names (DESCRIPTORS-DESIGN.md §4, slice 1): a dimmable and
/// a plain light, a light group, a cover with and one without position, a lock that can open, a fan with a speed
/// step, a cooling and a heating climate, a vacuum, a water heater and a plug. Ids and names are made up; the
/// attributes follow what Home Assistant core sends for each domain. The car, the boiler switch and the receiver
/// are `KhalaScreenFixtures`; the small home is `KhalaTestFixtures.home`.
enum KhalaKindFixtures {
    private typealias Base = KhalaTestFixtures

    /// Raw attributes by entity id, for the layouts and capability checks that read more than `KhalaEntity` keeps.
    static let attributes: [String: [String: Any]] = [
        // LightEntityFeature / ColorMode: `color_temp` dims and tunes white; `onoff` does neither.
        "light.desk_lamp": [
            "friendly_name": "Desk lamp", "supported_color_modes": ["color_temp"], "color_mode": "color_temp",
            "brightness": 178, "color_temp_kelvin": 2700, "min_color_temp_kelvin": 2200,
            "max_color_temp_kelvin": 6500, "supported_features": 0,
        ],
        "light.hall_bulb": [
            "friendly_name": "Hall bulb", "supported_color_modes": ["onoff"], "color_mode": "onoff",
            "supported_features": 0,
        ],
        // A light group: no device, its members in `entity_id`.
        "light.lounge_lights": [
            "friendly_name": "Lounge lights", "supported_color_modes": ["brightness"], "color_mode": "brightness",
            "brightness": 153, "entity_id": ["light.lounge_ceiling", "light.lounge_floor", "light.lounge_shelf"],
        ],
        "light.lounge_ceiling": ["friendly_name": "Lounge ceiling", "supported_color_modes": ["brightness"], "brightness": 204],
        "light.lounge_floor": ["friendly_name": "Lounge floor", "supported_color_modes": ["brightness"]],
        "light.lounge_shelf": ["friendly_name": "Lounge shelf", "supported_color_modes": ["hs"], "brightness": 102],
        // CoverEntityFeature: OPEN 1, CLOSE 2, SET_POSITION 4, STOP 8.
        "cover.shed_door": [
            "friendly_name": "Shed door", "device_class": "garage", "supported_features": 15, "current_position": 100,
        ],
        "cover.side_gate": ["friendly_name": "Side gate", "device_class": "gate", "supported_features": 3],
        // LockEntityFeature: OPEN 1.
        "lock.blue_door": ["friendly_name": "Blue door", "supported_features": 1],
        "sensor.blue_door_battery": [
            "friendly_name": "Blue door Battery", "device_class": "battery", "unit_of_measurement": "%",
        ],
        // FanEntityFeature: SET_SPEED 1, OSCILLATE 2, PRESET_MODE 8.
        "fan.attic_fan": [
            "friendly_name": "Attic fan", "supported_features": 11, "percentage": 50, "percentage_step": 25,
            "oscillating": false, "preset_modes": ["auto", "sleep"], "preset_mode": NSNull(),
        ],
        // ClimateEntityFeature: TARGET_TEMPERATURE 1, FAN_MODE 8, PRESET_MODE 16, SWING_MODE 32, OFF 128, ON 256.
        "climate.study_ac": [
            "friendly_name": "Study AC", "hvac_modes": ["off", "cool", "heat", "fan_only"], "min_temp": 16.0,
            "max_temp": 30.0, "target_temp_step": 0.5, "temperature": 22.5, "current_temperature": 26.0,
            "fan_modes": ["auto", "low", "high"], "fan_mode": "auto", "preset_modes": ["none", "eco"],
            "preset_mode": "none", "swing_modes": ["off", "vertical"], "swing_mode": "off", "supported_features": 441,
        ],
        "climate.loft_heater": [
            "friendly_name": "Loft heater", "hvac_modes": ["off", "heat"], "min_temp": 7.0, "max_temp": 35.0,
            "temperature": 20.0, "current_temperature": 18.5, "supported_features": 385,
        ],
        // VacuumEntityFeature: PAUSE 4, STOP 8, RETURN_HOME 16, FAN_SPEED 32, BATTERY 64, LOCATE 512, START 8192.
        "vacuum.dust_bot": [
            "friendly_name": "Dust bot", "supported_features": 8828, "fan_speed_list": ["quiet", "standard", "max"],
            "fan_speed": "standard", "battery_level": 100,
        ],
        "water_heater.cellar_tank": [
            "friendly_name": "Cellar tank", "current_temperature": 51.6, "temperature": 55.0,
            "operation_list": ["eco", "performance"], "operation_mode": "eco",
        ],
        "switch.desk_plug": ["friendly_name": "Desk plug", "device_class": "outlet"],
        "sensor.desk_plug_power": ["friendly_name": "Desk plug Power", "device_class": "power", "unit_of_measurement": "W"],
    ]

    static func entity(_ id: String, _ state: String, device: String? = nil, deviceName: String? = nil,
                       auxiliary: Bool = false) -> KhalaEntity {
        Base.entity(id, state, attributes[id] ?? [:], device: device, deviceName: deviceName, auxiliary: auxiliary)
    }

    static let deskLamp = entity("light.desk_lamp", "on", device: "dev-lamp", deviceName: "Desk lamp")
    static let hallBulb = entity("light.hall_bulb", "off", device: "dev-bulb", deviceName: "Hall bulb")
    static let loungeGroup = entity("light.lounge_lights", "on")
    static let loungeMembers = [
        entity("light.lounge_ceiling", "on"),
        entity("light.lounge_floor", "off"),
        entity("light.lounge_shelf", "on"),
    ]
    static let shedDoor = entity("cover.shed_door", "open", device: "dev-shed", deviceName: "Shed door")
    static let sideGate = entity("cover.side_gate", "closed", device: "dev-gate", deviceName: "Side gate")
    static let blueDoor = entity("lock.blue_door", "locked", device: "dev-blue", deviceName: "Blue door")
    static let blueDoorBattery = entity("sensor.blue_door_battery", "82", device: "dev-blue", deviceName: "Blue door")
    static let atticFan = entity("fan.attic_fan", "on", device: "dev-fan", deviceName: "Attic fan")
    static let studyAC = entity("climate.study_ac", "cool", device: "dev-ac", deviceName: "Study AC")
    static let loftHeater = entity("climate.loft_heater", "heat", device: "dev-loft", deviceName: "Loft heater")
    static let dustBot = entity("vacuum.dust_bot", "docked", device: "dev-bot", deviceName: "Dust bot")
    static let cellarTank = entity("water_heater.cellar_tank", "eco", device: "dev-cellar", deviceName: "Cellar tank")
    static let deskPlug = entity("switch.desk_plug", "on", device: "dev-plug", deviceName: "Desk plug")
    static let deskPlugPower = entity("sensor.desk_plug_power", "12.5", device: "dev-plug", deviceName: "Desk plug")

    /// Every kind fixture, in a fixed order.
    static var all: [KhalaEntity] {
        [deskLamp, hallBulb, loungeGroup] + loungeMembers + [
            shedDoor, sideGate, blueDoor, blueDoorBattery, atticFan, studyAC, loftHeater, dustBot, cellarTank,
            deskPlug, deskPlugPower,
        ]
    }

    /// Kinds plus the screen fixtures (car, boiler switch, receiver): one synthetic home of everything.
    static var everything: [KhalaEntity] {
        all + KhalaScreenFixtures.car + KhalaScreenFixtures.heater + [KhalaScreenFixtures.receiver]
    }

    /// Raw attributes of `everything`, merged.
    static var everythingAttributes: [String: [String: Any]] {
        var merged = attributes
        for (id, value) in KhalaScreenFixtures.carAttributes { merged[id] = value }
        merged[KhalaScreenFixtures.receiver.entityId] = KhalaScreenFixtures.receiverAttributes
        return merged
    }
}
