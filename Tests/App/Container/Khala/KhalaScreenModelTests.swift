import Foundation
@testable import HomeAssistant
import Testing

struct KhalaCarLayoutTests {
    private typealias Fixtures = KhalaScreenFixtures

    private var layout: KhalaCarLayout {
        KhalaCarLayout(name: "Rover", members: Fixtures.car, attributes: Fixtures.carAttributes)
    }

    @Test func readsBatteryRangeAndCharging() throws {
        let car = layout
        #expect(car.battery == 65)
        #expect(car.rangeText == "≈ 302 km")
        #expect(car.chargingText == "Not charging")
        #expect(car.isCharging == false)
        let limit = try #require(car.chargeLimit)
        #expect(limit.value == 80)
        #expect(limit.fraction == 0.6)
        #expect(limit.stepped(30) == 100)
        #expect(car.chargeCurrent?.maximum == 16)
        #expect(car.placeText == "At home")
        #expect(car.tracker?.entityId == "device_tracker.rover_location")
        #expect(car.wakeButtonId == "button.rover_wake")
        #expect(car.isAwake == false)
        #expect(car.insideTemperature == 27.4)
        #expect(car.outsideTemperature == 26.5)
    }

    @Test func overviewTilesFollowWhatTheCarExposes() {
        let titles = layout.overview.map(\.title)
        #expect(titles == ["Lock", "Sentry mode", "Charge port door", "Frunk", "Trunk", "Flash lights", "Honk horn"])
        let lock = layout.overview[0]
        #expect(lock.isActive)
        #expect(lock.call == KhalaServiceCallPlan(domain: "lock", service: "unlock", entityId: "lock.rover_lock"))
        #expect(lock.needsConfirmation)
        let sentry = layout.overview[1]
        #expect(sentry.call?.service == "turn_off")
        #expect(layout.overview.first { $0.title == "Flash lights" }?.call?.service == "press")
        #expect(layout.moreControls.map(\.title) == ["Homelink", "Play sound"])
        #expect(layout.mediaPlayerId == "media_player.rover_media_player")
        // Asleep: a refresh or a command wakes it and waits for the connectivity sensor.
        if case let .pressAndWait(button, connectivity) = layout.wakePlan {
            #expect(button == "button.rover_wake")
            #expect(connectivity.hasPrefix("binary_sensor."))
        } else {
            Issue.record("an asleep car with a wake button and a connectivity sensor should wake and wait")
        }
    }

    @Test func carMediaStaysOnTheCar() {
        let devices = KhalaDeviceCatalog.build(entities: KhalaScreenFixtures.car, assignments: [])
        #expect(devices.map(\.category) == [.car])
        #expect(devices.first?.memberEntityIds.contains("media_player.rover_media_player") == true)
    }

    @Test func frunkThatOnlyOpensHasNoActionOnceOpen() throws {
        let open = KhalaScreenFixtures.entity("cover.rover_frunk", "open", ["friendly_name": "Rover Frunk"],
                                              device: "dev-rover", deviceName: "Rover")
        let control = try #require(KhalaControl.make(open, attributes: ["supported_features": 1]))
        #expect(control.call == nil)
        #expect(control.isActive)
    }

    @Test func climateAndChargingTabsGetTheirOwnControls() throws {
        let car = layout
        #expect(car.climateControls.map(\.title).sorted() == ["Auto seat climate left", "Defrost", "Seat heater front left"])
        #expect(car.climateControls.first { $0.title == "Seat heater front left" }?.options.count == 4)
        #expect(car.chargingControls.map(\.title).sorted() == ["Charge", "Charge cable lock", "Charge port door"])
        let climate = try #require(car.climate)
        #expect(climate.isOn == false)
        #expect(climate.target?.value == 21)
        #expect(climate.target?.stepped(1) == 21.5)
        #expect(climate.onMode == "heat_cool")
        #expect(climate.setTarget(22).data["temperature"] as? Double == 22)
        #expect(climate.power(on: true).name == "climate.turn_on")
    }

    @Test func carWithoutExtrasGetsNoTiles() {
        let bare = KhalaCarLayout(name: "Basic", members: [
            KhalaScreenFixtures.entity("device_tracker.basic", "not_home", device: "dev-b"),
            KhalaScreenFixtures.entity("lock.basic", "unlocked", ["friendly_name": "Basic Door"], device: "dev-b"),
        ], attributes: [:])
        #expect(bare.overview.count == 1)
        #expect(bare.overview.first?.call?.service == "lock")
        #expect(bare.climate == nil)
        #expect(bare.chargeLimit == nil)
        #expect(bare.battery == nil)
        #expect(bare.placeText == "Away")
    }
}

struct KhalaHeatTests {
    private typealias Fixtures = KhalaScreenFixtures

    @Test func switcherHeatsWithItsOwnTimer() {
        let heat = KhalaHeatLayout(heater: Fixtures.heater[0], platform: "switcher_kis", members: Fixtures.heater)
        #expect(heat.isOn)
        #expect(heat.supportsDuration)
        #expect(heat.remaining.map { Int($0) } == 1930)
        #expect(heat.powerText == "2.5 kW")
        let call = heat.heatCall(minutes: 45)
        #expect(call.name == "switcher_kis.turn_on_with_timer")
        #expect(call.data["timer_minutes"] as? Int == 45)
        #expect(call.entityId == "switch.tank_9")
        #expect(heat.offCall.name == "switch.turn_off")
    }

    @Test func plainSwitchAndWaterHeaterJustTurnOn() {
        let plain = KhalaHeatLayout(heater: Fixtures.heater[0], platform: "shelly", members: [])
        #expect(!plain.supportsDuration)
        #expect(plain.heatCall(minutes: 45).name == "switch.turn_on")
        let tank = KhalaScreenFixtures.entity("water_heater.tank", "eco", ["current_temperature": 51.6])
        let heater = KhalaHeatLayout(heater: tank, platform: nil, members: [])
        #expect(heater.stateText == "52°")
        #expect(heater.heatCall(minutes: 30).name == "water_heater.turn_on")
    }

    @Test func remainingTimeFormats() {
        #expect(KhalaHeatLayout.seconds("00:32:10", unit: nil) == 1930)
        #expect(KhalaHeatLayout.seconds("12:30", unit: nil) == 750)
        #expect(KhalaHeatLayout.seconds("15", unit: "min") == 900)
        #expect(KhalaHeatLayout.seconds("90", unit: "s") == 90)
        #expect(KhalaHeatLayout.seconds("soon", unit: nil) == nil)
    }

    @Test func automationsThatTargetTheDeviceOrShareItsHelper() throws {
        let related = KhalaDeviceAutomations.related(
            to: ["switch.tank_9", "sensor.tank_9_remaining_time"],
            configs: Fixtures.heatConfigs,
            entities: Fixtures.heater,
            now: KhalaTestFixtures.now,
            horizon: 86400,
            calendar: KhalaTestFixtures.calendar
        )
        #expect(related.map(\.automationId) == ["automation.backup_check", "automation.backup_heat"])
        let check = related[0]
        #expect(!check.targetsDevice)
        #expect(check.isEnabled)
        #expect(check.description == "Books the morning run when it looks cloudy.")
        #expect(check.timesOfDay == [0])
        let heat = related[1]
        #expect(heat.targetsDevice)
        #expect(!heat.isEnabled)
        #expect(heat.runMinutes == 45)
        #expect(heat.timesOfDay == [7 * 3600 + 30 * 60])
        #expect(heat.toggleCall.name == "automation.turn_on")
        #expect(heat.fireDates.count == 1)
    }

    @Test func dialPutsMidnightAtTheBottomAndNoonOnTop() {
        #expect(KhalaDayDial.angle(secondsOfDay: 0) == 180)
        #expect(KhalaDayDial.angle(secondsOfDay: 6 * 3600) == 270)
        #expect(KhalaDayDial.angle(secondsOfDay: 12 * 3600) == 0)
        #expect(KhalaDayDial.angle(secondsOfDay: 18 * 3600) == 90)
        let top = KhalaDayDial.point(angle: 0, radius: 10)
        #expect(abs(top.x) < 1e-9 && abs(top.y + 10) < 1e-9)
        let right = KhalaDayDial.point(angle: 90, radius: 10)
        #expect(abs(right.x - 10) < 1e-9 && abs(right.y) < 1e-9)
        #expect(KhalaDayDial.sweep(.init(start: 23 * 3600, end: 3600)) == 30)
        #expect(KhalaDayDial.text(.init(start: 27000, end: 29700)) == "07:30–08:15")
    }

    @Test func dialHasTheSunBandTheBackupWindowAndNow() {
        let related = KhalaDeviceAutomations.related(
            to: ["switch.tank_9"], configs: Fixtures.heatConfigs, entities: Fixtures.heater,
            now: KhalaTestFixtures.now, horizon: 86400, calendar: KhalaTestFixtures.calendar
        )
        let sun = KhalaTestFixtures.home.first { $0.domain == "sun" }
        let dial = KhalaDayDial.build(sun: sun, automations: related, now: KhalaTestFixtures.now,
                                      calendar: KhalaTestFixtures.calendar)
        // Fixture sun: rises 06:48, sets 18:02 (UTC+3).
        #expect(dial.sun == .init(start: 6 * 3600 + 48 * 60 + 30, end: 18 * 3600 + 2 * 60 + 16))
        #expect(dial.windows == [.init(start: 27000, end: 29700)])
        #expect(dial.now == 12 * 3600)
    }
}

struct KhalaMediaLayoutTests {
    @Test func receiverOffersEverythingItSupports() {
        let media = KhalaMediaLayout(entity: KhalaScreenFixtures.receiver, attributes: KhalaScreenFixtures.receiverAttributes)
        #expect(media.isOn)
        #expect(media.canPower)
        #expect(media.volume == 0.455)
        #expect(media.sources == ["Bluetooth", "Music", "Console"])
        #expect(media.soundModes.count == 3)
        #expect(media.stateLine == "On · Music")
        #expect(media.setVolume(0.456).data["volume_level"] as? Double == 0.46)
        #expect(media.setVolume(1.4).data["volume_level"] as? Double == 1)
        #expect(media.selectSource("Console").data["source"] as? String == "Console")
        #expect(media.selectSoundMode("MOVIE").name == "media_player.select_sound_mode")
        #expect(media.power(on: false).name == "media_player.turn_off")
        #expect(KhalaMediaLayout.volumeText(0.455) == "46%")
    }

    @Test func speakerWithoutSourcesOrModesHidesThem() {
        let speaker = KhalaScreenFixtures.entity("media_player.kitchen", "playing", ["device_class": "speaker"])
        let media = KhalaMediaLayout(entity: speaker, attributes: [
            "supported_features": 16437, "volume_level": 0.3, "source": "Radio", "source_list": ["Radio"],
        ])
        #expect(media.sources.isEmpty) // no SELECT_SOURCE flag
        #expect(media.soundModes.isEmpty)
        #expect(media.volume == 0.3)
        #expect(media.stateLine == "Playing · Radio")
    }

    @Test func offReceiverHasNoVolume() {
        let off = KhalaScreenFixtures.entity("media_player.den_receiver", "off", ["device_class": "receiver"])
        let media = KhalaMediaLayout(entity: off, attributes: ["supported_features": 69004])
        #expect(!media.isOn)
        #expect(media.volume == nil)
        #expect(media.stateLine == "Off")
    }
}
