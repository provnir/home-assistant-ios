import Foundation
@testable import HomeAssistant
import Testing

/// Characterization tests: what the device catalog, the category/colour mapping, routing, the glyph rules and the
/// car/heat/media layouts produce TODAY (TestFlight 41.1, khala 8b543f6d4), recorded as text. They were written and
/// passing before the descriptor refactor (DESCRIPTORS-DESIGN.md §4, slice 1) and must keep passing unchanged
/// through it: a failure here is a visible change. Re-record only for a change Nir asked for (`KhalaGolden.matches`).
struct KhalaGoldenTests {
    private typealias Kinds = KhalaKindFixtures
    private typealias Home = KhalaTestFixtures
    private typealias Screens = KhalaScreenFixtures

    /// Every legacy role on entities of many domains, a blank label, and an entity that no longer exists.
    static let pins = [
        KhalaRoleAssignment(entityId: "switch.relay_7", role: .heat, label: "Hot water"),
        KhalaRoleAssignment(entityId: "light.desk_lamp", role: .neutral, label: nil),
        KhalaRoleAssignment(entityId: "lock.blue_door", role: .security, label: "Door"),
        KhalaRoleAssignment(entityId: "camera.porch", role: .security, label: nil),
        KhalaRoleAssignment(entityId: "climate.study_ac", role: .heat, label: nil),
        KhalaRoleAssignment(entityId: "media_player.kitchen_speaker", role: .media, label: " "),
        KhalaRoleAssignment(entityId: "device_tracker.phone", role: .car, label: nil),
        KhalaRoleAssignment(entityId: "vacuum.dust_bot", role: .neutral, label: nil),
        KhalaRoleAssignment(entityId: "light.lounge_lights", role: .neutral, label: nil),
        KhalaRoleAssignment(entityId: "event.yard_field_detection", role: .security, label: nil),
        KhalaRoleAssignment(entityId: "switch.gone", role: .heat, label: nil),
    ]

    static var pinnedHome: [KhalaEntity] { Home.home + Kinds.all }

    // MARK: - Catalog

    @Test func catalogOfTheSmallHome() {
        let devices = KhalaDeviceCatalog.build(entities: Home.home, assignments: [])
        #expect(KhalaGolden.matches("catalog-home", KhalaGolden.devices(devices), """
        dev-rover | Rover | car | sensor.rover_battery_level | 72% | detected | device_tracker.rover_location,lock.rover_lock,sensor.rover_battery_level,switch.rover_defrost,media_player.rover_media,sensor.rover_time_to_full_charge
        dev-den | Den | media | media_player.den_receiver | Off | detected | media_player.den_zone_2,media_player.den_receiver
        dev-kitchen | Kitchen speaker | media | media_player.kitchen_speaker | Playing | detected | media_player.kitchen_speaker
        dev-relay | Relay 7 | neutral | switch.relay_7 | Off | detected | switch.relay_7,sensor.relay_7_power
        """))
    }

    @Test func catalogOfEveryKind() {
        let devices = KhalaDeviceCatalog.build(entities: Kinds.everything, assignments: [])
        #expect(KhalaGolden.matches("catalog-everything", KhalaGolden.devices(devices), """
        dev-rover | Rover | car | sensor.rover_battery_level | 65% | detected | device_tracker.rover_location,device_tracker.rover_route,lock.rover_lock,lock.rover_charge_cable_lock,sensor.rover_battery_level,sensor.rover_battery_range,sensor.rover_charging,sensor.rover_charger_power,sensor.rover_inside_temperature,sensor.rover_outside_temperature,number.rover_charge_limit,number.rover_charge_current,binary_sensor.rover_status,binary_sensor.rover_charge_cable,climate.rover_climate,switch.rover_sentry_mode,switch.rover_defrost,switch.rover_charge,switch.rover_auto_seat_climate_left,cover.rover_charge_port_door,cover.rover_frunk,cover.rover_trunk,button.rover_wake,button.rover_flash_lights,button.rover_honk_horn,button.rover_homelink,button.rover_play_sound,media_player.rover_media_player,select.rover_seat_heater_front_left,update.rover_update
        dev-cellar | Cellar tank | heat | water_heater.cellar_tank | 52° | detected | water_heater.cellar_tank
        dev-loft | Loft heater | heat | climate.loft_heater | 19° | detected | climate.loft_heater
        dev-ac | Study AC | heat | climate.study_ac | 26° | detected | climate.study_ac
        dev-den | Den | media | media_player.den_receiver | On | detected | media_player.den_receiver
        dev-blue | Blue door | security | lock.blue_door | Locked | detected | lock.blue_door,sensor.blue_door_battery
        dev-shed | Shed door | neutral | cover.shed_door | Open | detected | cover.shed_door
        dev-gate | Side gate | neutral | cover.side_gate | Closed | detected | cover.side_gate
        dev-fan | Attic fan | neutral | fan.attic_fan | On | detected | fan.attic_fan
        dev-plug | Desk plug | neutral | switch.desk_plug | On | detected | switch.desk_plug,sensor.desk_plug_power
        entity:switch.other | Other | neutral | switch.other | Off | detected | switch.other
        dev-tank | Tank 9 | neutral | switch.tank_9 | On | detected | switch.tank_9,sensor.tank_9_remaining_time,sensor.tank_9_power
        entity:light.lounge_lights | Lounge lights | sun | light.lounge_lights | On | detected | light.lounge_lights
        dev-lamp | Desk lamp | sun | light.desk_lamp | On | detected | light.desk_lamp
        dev-bulb | Hall bulb | sun | light.hall_bulb | Off | detected | light.hall_bulb
        """))
    }

    @Test func catalogWithEveryLegacyRolePinned() {
        let devices = KhalaDeviceCatalog.build(entities: Self.pinnedHome, assignments: Self.pins)
        #expect(KhalaGolden.matches("catalog-pins", KhalaGolden.devices(devices), """
        pin:switch.relay_7 | Hot water | heat | switch.relay_7 | Off | pinned | switch.relay_7,sensor.relay_7_power
        pin:light.desk_lamp | Desk lamp | neutral | light.desk_lamp | On | pinned | light.desk_lamp
        pin:lock.blue_door | Door | security | lock.blue_door | Locked | pinned | lock.blue_door,sensor.blue_door_battery
        pin:camera.porch | Porch | security | camera.porch | Idle | pinned | camera.porch,event.porch_field_detection,event.porch_line_crossing
        pin:climate.study_ac | Study AC | heat | climate.study_ac | 26° | pinned | climate.study_ac
        pin:media_player.kitchen_speaker | Kitchen | media | media_player.kitchen_speaker | Playing | pinned | media_player.kitchen_speaker
        pin:device_tracker.phone | Phone | car | device_tracker.phone | Home | pinned | device_tracker.phone,sensor.phone_battery_level
        pin:vacuum.dust_bot | Dust bot | neutral | vacuum.dust_bot | Docked | pinned | vacuum.dust_bot
        pin:light.lounge_lights | Lounge lights | neutral | light.lounge_lights | On | pinned | light.lounge_lights
        pin:event.yard_field_detection | Yard Field detection | security | event.yard_field_detection | 2026-10-19T18:00:50.077+00:00 | pinned | camera.yard,event.yard_field_detection
        dev-rover | Rover | car | sensor.rover_battery_level | 72% | detected | device_tracker.rover_location,lock.rover_lock,sensor.rover_battery_level,switch.rover_defrost,media_player.rover_media,sensor.rover_time_to_full_charge
        dev-cellar | Cellar tank | heat | water_heater.cellar_tank | 52° | detected | water_heater.cellar_tank
        dev-loft | Loft heater | heat | climate.loft_heater | 19° | detected | climate.loft_heater
        dev-den | Den | media | media_player.den_receiver | Off | detected | media_player.den_zone_2,media_player.den_receiver
        dev-shed | Shed door | neutral | cover.shed_door | Open | detected | cover.shed_door
        dev-gate | Side gate | neutral | cover.side_gate | Closed | detected | cover.side_gate
        dev-fan | Attic fan | neutral | fan.attic_fan | On | detected | fan.attic_fan
        dev-plug | Desk plug | neutral | switch.desk_plug | On | detected | switch.desk_plug,sensor.desk_plug_power
        dev-bulb | Hall bulb | sun | light.hall_bulb | Off | detected | light.hall_bulb
        """))
    }

    @Test func nowChipsAndAutomationColours() {
        let home = KhalaDeviceCatalog.build(entities: Home.home, assignments: [])
        let pinned = KhalaDeviceCatalog.build(entities: Self.pinnedHome, assignments: Self.pins)
        let everything = KhalaDeviceCatalog.build(entities: Kinds.everything, assignments: [])
        let colours = KhalaDeviceCatalog.categoryByEntityId(pinned)
            .sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value.rawValue)" }
        let text = [
            "home: " + KhalaDeviceCatalog.nowChips(from: home).map(\.id).joined(separator: ", "),
            "pins: " + KhalaDeviceCatalog.nowChips(from: pinned).map(\.id).joined(separator: ", "),
            "pins(5): " + KhalaDeviceCatalog.nowChips(from: pinned, limit: 5).map(\.id).joined(separator: ", "),
            "everything: " + KhalaDeviceCatalog.nowChips(from: everything).map(\.id).joined(separator: ", "),
        ] + colours
        #expect(KhalaGolden.matches("now-chips", text.joined(separator: "\n"), """
        home: dev-rover, dev-den, dev-relay
        pins: pin:switch.relay_7, pin:light.desk_lamp, pin:lock.blue_door
        pins(5): pin:switch.relay_7, pin:light.desk_lamp, pin:lock.blue_door, pin:camera.porch, pin:climate.study_ac
        everything: dev-rover, dev-cellar, dev-den
        camera.porch security
        camera.yard security
        climate.loft_heater heat
        climate.study_ac heat
        cover.shed_door neutral
        cover.side_gate neutral
        device_tracker.phone car
        device_tracker.rover_location car
        event.porch_field_detection security
        event.porch_line_crossing security
        event.yard_field_detection security
        fan.attic_fan neutral
        light.desk_lamp neutral
        light.hall_bulb sun
        light.lounge_lights neutral
        lock.blue_door security
        lock.rover_lock car
        media_player.den_receiver media
        media_player.den_zone_2 media
        media_player.kitchen_speaker media
        media_player.rover_media car
        sensor.blue_door_battery security
        sensor.desk_plug_power neutral
        sensor.phone_battery_level car
        sensor.relay_7_power heat
        sensor.rover_battery_level car
        sensor.rover_time_to_full_charge car
        switch.desk_plug neutral
        switch.relay_7 heat
        switch.rover_defrost car
        vacuum.dust_bot neutral
        water_heater.cellar_tank heat
        """))
    }

    // MARK: - Routing

    @Test func everyEntityOfTheHomeRoutesWhereItDoesToday() {
        let devices = KhalaDeviceCatalog.build(entities: Home.home, assignments: [])
        let configs = [
            "automation.midnight_check": Home.midnightCheckConfig,
            "automation.evening_lights": Home.eveningLightsConfig,
        ]
        let lines = (Home.home.map(\.entityId) + ["light.not_there"]).map { entityId in
            entityId + " -> " + KhalaGolden.route(KhalaRouting.target(
                forEntityId: entityId, entities: Home.home, devices: devices, automationConfigs: configs
            ))
        }
        #expect(KhalaGolden.matches("routes-home", lines.joined(separator: "\n"), """
        sun.sun -> screen entity(sun.sun)
        weather.home -> screen entity(weather.home)
        camera.porch -> screen camera(camera.porch)
        event.porch_field_detection -> screen camera(camera.porch)
        event.porch_line_crossing -> screen camera(camera.porch)
        camera.yard -> screen camera(camera.yard)
        event.yard_field_detection -> screen camera(camera.yard)
        device_tracker.rover_location -> screen device(dev-rover)
        lock.rover_lock -> screen device(dev-rover)
        sensor.rover_battery_level -> screen device(dev-rover)
        switch.rover_defrost -> screen device(dev-rover)
        media_player.rover_media -> screen device(dev-rover)
        sensor.rover_time_to_full_charge -> screen device(dev-rover)
        media_player.den_zone_2 -> sheet dev-den media_player.den_receiver
        media_player.den_receiver -> sheet dev-den media_player.den_receiver
        media_player.kitchen_speaker -> sheet dev-kitchen media_player.kitchen_speaker
        switch.relay_7 -> screen device(dev-relay)
        sensor.relay_7_power -> screen device(dev-relay)
        device_tracker.phone -> screen entity(device_tracker.phone)
        sensor.phone_battery_level -> screen entity(sensor.phone_battery_level)
        automation.midnight_check -> screen device(dev-relay)
        automation.evening_lights -> screen device(dev-relay)
        input_datetime.wake_up -> screen entity(input_datetime.wake_up)
        light.not_there -> screen entity(light.not_there)
        """))
    }

    @Test func pinnedAndDetectedDevicesRouteByTheirRole() {
        let entities = Self.pinnedHome + Kinds.everything.filter { !Self.pinnedHome.map(\.entityId).contains($0.entityId) }
        let devices = KhalaDeviceCatalog.build(entities: entities, assignments: Self.pins)
        let cameras = entities.filter { $0.domain == "camera" }
        let byDevice = devices.map { "\($0.id) -> " + KhalaGolden.route(KhalaRouting.target(for: $0, cameras: cameras)) }
        let byEntity = Kinds.all.map(\.entityId).map { entityId in
            entityId + " -> " + KhalaGolden.route(KhalaRouting.target(
                forEntityId: entityId, entities: entities, devices: devices, automationConfigs: [:]
            ))
        }
        #expect(KhalaGolden.matches("routes-pins", (byDevice + byEntity).joined(separator: "\n"), """
        pin:switch.relay_7 -> screen device(pin:switch.relay_7)
        pin:light.desk_lamp -> screen device(pin:light.desk_lamp)
        pin:lock.blue_door -> screen device(pin:lock.blue_door)
        pin:camera.porch -> screen camera(camera.porch)
        pin:climate.study_ac -> screen device(pin:climate.study_ac)
        pin:media_player.kitchen_speaker -> sheet pin:media_player.kitchen_speaker media_player.kitchen_speaker
        pin:device_tracker.phone -> screen device(pin:device_tracker.phone)
        pin:vacuum.dust_bot -> screen device(pin:vacuum.dust_bot)
        pin:light.lounge_lights -> screen device(pin:light.lounge_lights)
        pin:event.yard_field_detection -> screen camera(camera.yard)
        dev-rover -> screen device(dev-rover)
        dev-cellar -> screen device(dev-cellar)
        dev-loft -> screen device(dev-loft)
        dev-den -> sheet dev-den media_player.den_receiver
        dev-shed -> screen device(dev-shed)
        dev-gate -> screen device(dev-gate)
        dev-fan -> screen device(dev-fan)
        dev-plug -> screen device(dev-plug)
        entity:switch.other -> screen device(entity:switch.other)
        dev-tank -> screen device(dev-tank)
        dev-bulb -> screen device(dev-bulb)
        light.desk_lamp -> screen device(pin:light.desk_lamp)
        light.hall_bulb -> screen device(dev-bulb)
        light.lounge_lights -> screen device(pin:light.lounge_lights)
        light.lounge_ceiling -> screen entity(light.lounge_ceiling)
        light.lounge_floor -> screen entity(light.lounge_floor)
        light.lounge_shelf -> screen entity(light.lounge_shelf)
        cover.shed_door -> screen device(dev-shed)
        cover.side_gate -> screen device(dev-gate)
        lock.blue_door -> screen device(pin:lock.blue_door)
        sensor.blue_door_battery -> screen device(pin:lock.blue_door)
        fan.attic_fan -> screen device(dev-fan)
        climate.study_ac -> screen device(pin:climate.study_ac)
        climate.loft_heater -> screen device(dev-loft)
        vacuum.dust_bot -> screen device(pin:vacuum.dust_bot)
        water_heater.cellar_tank -> screen device(dev-cellar)
        switch.desk_plug -> screen device(dev-plug)
        sensor.desk_plug_power -> screen device(dev-plug)
        """))
    }

    // MARK: - Category / colour mapping

    @Test func rolesAndTheirOrder() {
        let domains = [
            "water_heater", "climate", "boiler", "media_player", "remote", "camera", "event", "alarm_control_panel",
            "lock", "device_tracker", "switch", "light", "cover", "fan", "vacuum", "sensor", "button", "",
        ]
        var lines: [String] = []
        lines.append("all: " + KhalaAccent.allCases.map(\.rawValue).joined(separator: ","))
        lines.append("assignable: " + KhalaAccent.assignableRoles.map(\.rawValue).joined(separator: ","))
        lines.append("chips: " + KhalaAccent.chipPriority.map(\.rawValue).joined(separator: ","))
        for category in KhalaAccent.allCases {
            lines.append("\(category.rawValue) = \(category.displayName)")
        }
        for domain in domains {
            lines.append("suggest \(domain) -> \(KhalaAccent.suggestedRole(forDomain: domain).rawValue)")
        }
        #expect(KhalaGolden.matches("roles", lines.joined(separator: "\n"), """
        all: security,car,heat,media,sun,neutral
        assignable: car,heat,media,security,neutral
        chips: car,heat,media,security,neutral
        security = Security
        car = Car
        heat = Hot water / heat
        media = Media
        sun = Sun
        neutral = Other
        suggest water_heater -> heat
        suggest climate -> heat
        suggest boiler -> heat
        suggest media_player -> media
        suggest remote -> media
        suggest camera -> security
        suggest event -> security
        suggest alarm_control_panel -> security
        suggest lock -> security
        suggest device_tracker -> car
        suggest switch -> neutral
        suggest light -> neutral
        suggest cover -> neutral
        suggest fan -> neutral
        suggest vacuum -> neutral
        suggest sensor -> neutral
        suggest button -> neutral
        suggest  -> neutral
        """))
    }

    @Test func legacyStoredAssignmentsStillLoad() throws {
        // The JSON 41.1 writes into the shared defaults, byte for byte.
        let stored = #"[{"entityId":"switch.relay_7","role":"heat","label":"Hot water"},"#
            + #"{"entityId":"lock.blue_door","role":"security"},{"entityId":"camera.porch","role":"security"},"#
            + #"{"entityId":"media_player.den_receiver","role":"media","label":null},"#
            + #"{"entityId":"device_tracker.phone","role":"car"},{"entityId":"light.desk_lamp","role":"neutral"}]"#
        let suite = "khala-golden-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(stored.utf8), forKey: KhalaRoleAssignmentStore.key(serverId: "s"))
        let loaded = KhalaRoleAssignmentStore(defaults: defaults).load(serverId: "s")
        #expect(loaded == [
            KhalaRoleAssignment(entityId: "switch.relay_7", role: .heat, label: "Hot water"),
            KhalaRoleAssignment(entityId: "lock.blue_door", role: .security, label: nil),
            KhalaRoleAssignment(entityId: "camera.porch", role: .security, label: nil),
            KhalaRoleAssignment(entityId: "media_player.den_receiver", role: .media, label: nil),
            KhalaRoleAssignment(entityId: "device_tracker.phone", role: .car, label: nil),
            KhalaRoleAssignment(entityId: "light.desk_lamp", role: .neutral, label: nil),
        ])
        #expect(loaded.map(\.role) == [.heat, .security, .security, .media, .car, .neutral])
        let devices = KhalaDeviceCatalog.build(entities: Self.pinnedHome, assignments: loaded)
        #expect(KhalaGolden.matches("legacy-pins", KhalaGolden.devices(devices.filter(\.isPinned)), """
        pin:switch.relay_7 | Hot water | heat | switch.relay_7 | Off | pinned | switch.relay_7,sensor.relay_7_power
        pin:lock.blue_door | Blue door | security | lock.blue_door | Locked | pinned | lock.blue_door,sensor.blue_door_battery
        pin:camera.porch | Porch | security | camera.porch | Idle | pinned | camera.porch,event.porch_field_detection,event.porch_line_crossing
        pin:media_player.den_receiver | Den Receiver | media | media_player.den_receiver | Off | pinned | media_player.den_zone_2,media_player.den_receiver
        pin:device_tracker.phone | Phone | car | device_tracker.phone | Home | pinned | device_tracker.phone,sensor.phone_battery_level
        pin:light.desk_lamp | Desk lamp | neutral | light.desk_lamp | On | pinned | light.desk_lamp
        """))
    }

    @Test func savedAssignmentsStayReadableByTheOldBuild() throws {
        // What the old build decodes: `role` as one of the six category strings. A downgrade must keep the pins.
        struct OldAssignment: Decodable, Equatable {
            let entityId: String
            let role: String
            let label: String?
        }
        let data = try JSONEncoder().encode(Self.pins)
        let old = try JSONDecoder().decode([OldAssignment].self, from: data)
        #expect(old.map(\.entityId) == Self.pins.map(\.entityId))
        #expect(old.map(\.role) == Self.pins.map(\.role.rawValue))
        #expect(old.map(\.label) == Self.pins.map(\.label))
        #expect(try JSONDecoder().decode([KhalaRoleAssignment].self, from: data) == Self.pins)
    }

    @Test func timelineRowsKeepTheirColour() {
        let devices = KhalaDeviceCatalog.build(entities: Home.home, assignments: [])
        let timeline = KhalaTimeline.build(
            entities: Home.home,
            devices: devices,
            automationConfigs: [
                "automation.midnight_check": Home.midnightCheckConfig,
                "automation.evening_lights": Home.eveningLightsConfig,
            ],
            now: Home.now,
            calendar: Home.calendar
        )
        let lines = timeline.items.map {
            "\($0.id) | \($0.title) | \($0.category.rawValue) | \($0.isNow ? "now" : $0.isPast ? "past" : "upcoming")"
        } + ["chips: " + timeline.chips.map(\.id).joined(separator: ", ")]
        #expect(KhalaGolden.matches("timeline", lines.joined(separator: "\n"), """
        scheduled:automation.midnight_check:1792530000 | Midnight check | neutral | upcoming
        timestamp:sensor.rover_time_to_full_charge | Rover Time to full charge | car | upcoming
        sun:Sunset | Sunset | sun | upcoming
        now | Now | neutral | now
        detection:event.porch_field_detection | Person at Porch | security | past
        sun:Sunrise | Sunrise | sun | past
        chips: dev-rover, dev-den, dev-relay
        """))
    }

    // MARK: - Glyphs and tiles

    /// Re-recorded in slice 5 (no word matching left in Model): the last six rows and `automation.evening_lights`
    /// are entities of no integration whose glyph 41.1 took from words in their ids ("guard", "window", "light",
    /// "steering", "boot", "fan"); they now fall back to domain and device class. Every car, heater and media row is
    /// unchanged, from the hints file.
    @Test func glyphsForEveryFixture() {
        let entities = Kinds.everything + Home.home + [
            Kinds.entity("switch.garage_guard", "on"),
            Kinds.entity("cover.living_window", "closed"),
            Kinds.entity("button.porch_light_flash", "unknown"),
            Kinds.entity("switch.steering_wheel_heater", "off"),
            Kinds.entity("select.boot_mode", "off"),
            Kinds.entity("number.climate_fan_speed", "3"),
        ]
        let lines = entities.map { "\($0.entityId) \($0.state) -> \(KhalaIconChain.tileGlyph(for: $0).rawValue)" }
        #expect(KhalaGolden.matches("glyphs", lines.joined(separator: "\n"), """
        light.desk_lamp on -> lights
        light.hall_bulb off -> lights
        light.lounge_lights on -> lights
        light.lounge_ceiling on -> lights
        light.lounge_floor off -> lights
        light.lounge_shelf on -> lights
        cover.shed_door open -> generic
        cover.side_gate closed -> generic
        lock.blue_door locked -> lock
        sensor.blue_door_battery 82 -> generic
        fan.attic_fan on -> fan
        climate.study_ac cool -> fan
        climate.loft_heater heat -> fan
        vacuum.dust_bot docked -> generic
        water_heater.cellar_tank eco -> generic
        switch.desk_plug on -> power
        sensor.desk_plug_power 12.5 -> generic
        device_tracker.rover_location home -> generic
        device_tracker.rover_route not_home -> generic
        lock.rover_lock locked -> lock
        lock.rover_charge_cable_lock locked -> lock
        sensor.rover_battery_level 65 -> generic
        sensor.rover_battery_range 301.57 -> generic
        sensor.rover_charging disconnected -> generic
        sensor.rover_charger_power 0 -> generic
        sensor.rover_inside_temperature 27.4 -> generic
        sensor.rover_outside_temperature 26.5 -> generic
        number.rover_charge_limit 80 -> generic
        number.rover_charge_current 16 -> generic
        binary_sensor.rover_status off -> generic
        binary_sensor.rover_charge_cable off -> generic
        climate.rover_climate off -> fan
        switch.rover_sentry_mode on -> shield
        switch.rover_defrost off -> defrost
        switch.rover_charge off -> power
        switch.rover_auto_seat_climate_left off -> seat
        cover.rover_charge_port_door closed -> chargePort
        cover.rover_frunk closed -> frunk
        cover.rover_trunk closed -> trunk
        button.rover_wake unknown -> button
        button.rover_flash_lights unknown -> lights
        button.rover_honk_horn unknown -> horn
        button.rover_homelink unknown -> button
        button.rover_play_sound unknown -> button
        media_player.rover_media_player paused -> generic
        select.rover_seat_heater_front_left off -> seat
        update.rover_update off -> generic
        switch.tank_9 on -> power
        sensor.tank_9_remaining_time 00:32:10 -> generic
        sensor.tank_9_power 2450 -> generic
        input_boolean.backup_booked off -> generic
        automation.backup_check on -> generic
        automation.backup_heat off -> generic
        automation.unrelated on -> generic
        switch.other off -> power
        media_player.den_receiver on -> generic
        sun.sun above_horizon -> generic
        weather.home sunny -> generic
        camera.porch idle -> generic
        event.porch_field_detection 2026-10-20T07:35:02.953+00:00 -> generic
        event.porch_line_crossing unknown -> generic
        camera.yard idle -> generic
        event.yard_field_detection 2026-10-19T18:00:50.077+00:00 -> generic
        device_tracker.rover_location not_home -> generic
        lock.rover_lock locked -> lock
        sensor.rover_battery_level 72 -> generic
        switch.rover_defrost off -> defrost
        media_player.rover_media paused -> generic
        sensor.rover_time_to_full_charge 2026-10-20T16:30:00+00:00 -> generic
        media_player.den_zone_2 off -> generic
        media_player.den_receiver off -> generic
        media_player.kitchen_speaker playing -> generic
        switch.relay_7 off -> power
        sensor.relay_7_power 0 -> generic
        device_tracker.phone home -> generic
        sensor.phone_battery_level 65 -> generic
        automation.midnight_check on -> generic
        automation.evening_lights off -> generic
        input_datetime.wake_up 06:30:00 -> generic
        switch.garage_guard on -> power
        cover.living_window closed -> generic
        button.porch_light_flash unknown -> button
        switch.steering_wheel_heater off -> power
        select.boot_mode off -> generic
        number.climate_fan_speed 3 -> generic
        """))
    }

    /// Re-recorded in slice 5: only `button.reboot` changed ("trunk", from the word "boot" in "reboot", is now the
    /// plain button glyph).
    @Test func tilesForEveryFixture() {
        let attributes = Kinds.everythingAttributes
        let extra: [(KhalaEntity, [String: Any])] = [
            (Kinds.entity("lock.blue_door", "unlocked", device: "dev-blue", deviceName: "Blue door"), [:]),
            (Kinds.entity("lock.blue_door", "unknown", device: "dev-blue", deviceName: "Blue door"), [:]),
            (Kinds.entity("cover.side_gate", "open", device: "dev-gate", deviceName: "Side gate"), ["supported_features": 1]),
            (Kinds.entity("cover.side_gate", "closed", device: "dev-gate", deviceName: "Side gate"), [:]),
            (Kinds.entity("switch.desk_plug", "unavailable", device: "dev-plug", deviceName: "Desk plug"), [:]),
            (Kinds.entity("button.reboot", "unavailable"), [:]),
            (Kinds.entity("input_boolean.guest_mode", "on"), [:]),
            (Kinds.entity("input_select.scene_mode", "evening"), ["options": ["day", "evening"]]),
            (Kinds.entity("select.preset", "unavailable"), ["options": ["a", "b"]]),
        ]
        let entities = (Kinds.everything + Home.home).map { ($0, attributes[$0.entityId] ?? [:]) } + extra
        let lines = entities.map { entity, attributes in
            KhalaControl.make(entity, attributes: attributes).map(KhalaGolden.control) ?? "\(entity.entityId) | none"
        }
        #expect(KhalaGolden.matches("tiles", lines.joined(separator: "\n"), """
        light.desk_lamp | Desk lamp | On | lights | active | light.turn_off(light.desk_lamp) | - | -
        light.hall_bulb | Hall bulb | Off | lights | idle | light.turn_on(light.hall_bulb) | - | -
        light.lounge_lights | Lounge lights | On | lights | active | light.turn_off(light.lounge_lights) | - | -
        light.lounge_ceiling | Lounge ceiling | On | lights | active | light.turn_off(light.lounge_ceiling) | - | -
        light.lounge_floor | Lounge floor | Off | lights | idle | light.turn_on(light.lounge_floor) | - | -
        light.lounge_shelf | Lounge shelf | On | lights | active | light.turn_off(light.lounge_shelf) | - | -
        cover.shed_door | Shed door | Open | generic | active | cover.close_cover(cover.shed_door) | - | -
        cover.side_gate | Side gate | Closed | generic | idle | cover.open_cover(cover.side_gate) | - | confirm
        lock.blue_door | Blue door | Locked | lock | active | lock.unlock(lock.blue_door) | - | confirm
        sensor.blue_door_battery | none
        fan.attic_fan | Attic fan | On | fan | active | fan.turn_off(fan.attic_fan) | - | -
        climate.study_ac | none
        climate.loft_heater | none
        vacuum.dust_bot | none
        water_heater.cellar_tank | none
        switch.desk_plug | Desk plug | On | power | active | switch.turn_off(switch.desk_plug) | - | -
        sensor.desk_plug_power | none
        device_tracker.rover_location | none
        device_tracker.rover_route | none
        lock.rover_lock | Lock | Locked | lock | active | lock.unlock(lock.rover_lock) | - | confirm
        lock.rover_charge_cable_lock | Charge cable lock | Locked | lock | active | lock.unlock(lock.rover_charge_cable_lock) | - | confirm
        sensor.rover_battery_level | none
        sensor.rover_battery_range | none
        sensor.rover_charging | none
        sensor.rover_charger_power | none
        sensor.rover_inside_temperature | none
        sensor.rover_outside_temperature | none
        number.rover_charge_limit | none
        number.rover_charge_current | none
        binary_sensor.rover_status | none
        binary_sensor.rover_charge_cable | none
        climate.rover_climate | none
        switch.rover_sentry_mode | Sentry mode | On | shield | active | switch.turn_off(switch.rover_sentry_mode) | - | -
        switch.rover_defrost | Defrost | Off | defrost | idle | switch.turn_on(switch.rover_defrost) | - | -
        switch.rover_charge | Charge | Off | power | idle | switch.turn_on(switch.rover_charge) | - | -
        switch.rover_auto_seat_climate_left | Auto seat climate left | Off | seat | idle | switch.turn_on(switch.rover_auto_seat_climate_left) | - | -
        cover.rover_charge_port_door | Charge port door | Closed | chargePort | idle | cover.open_cover(cover.rover_charge_port_door) | - | confirm
        cover.rover_frunk | Frunk | Closed | frunk | idle | cover.open_cover(cover.rover_frunk) | - | confirm
        cover.rover_trunk | Trunk | Closed | trunk | idle | cover.open_cover(cover.rover_trunk) | - | confirm
        button.rover_wake | Wake |  | button | idle | button.press(button.rover_wake) | - | -
        button.rover_flash_lights | Flash lights |  | lights | idle | button.press(button.rover_flash_lights) | - | -
        button.rover_honk_horn | Honk horn |  | horn | idle | button.press(button.rover_honk_horn) | - | -
        button.rover_homelink | Homelink |  | button | idle | button.press(button.rover_homelink) | - | -
        button.rover_play_sound | Play sound |  | button | idle | button.press(button.rover_play_sound) | - | -
        media_player.rover_media_player | none
        select.rover_seat_heater_front_left | Seat heater front left | Off | seat | idle | - | off/low/medium/high | -
        update.rover_update | none
        switch.tank_9 | Tank 9 | On | power | active | switch.turn_off(switch.tank_9) | - | -
        sensor.tank_9_remaining_time | none
        sensor.tank_9_power | none
        input_boolean.backup_booked | Backup booked | Off | generic | idle | input_boolean.turn_on(input_boolean.backup_booked) | - | -
        automation.backup_check | none
        automation.backup_heat | none
        automation.unrelated | none
        switch.other | Other | Off | power | idle | switch.turn_on(switch.other) | - | -
        media_player.den_receiver | none
        sun.sun | none
        weather.home | none
        camera.porch | none
        event.porch_field_detection | none
        event.porch_line_crossing | none
        camera.yard | none
        event.yard_field_detection | none
        device_tracker.rover_location | none
        lock.rover_lock | Lock | Locked | lock | active | lock.unlock(lock.rover_lock) | - | confirm
        sensor.rover_battery_level | none
        switch.rover_defrost | Defrost | Off | defrost | idle | switch.turn_on(switch.rover_defrost) | - | -
        media_player.rover_media | none
        sensor.rover_time_to_full_charge | none
        media_player.den_zone_2 | none
        media_player.den_receiver | none
        media_player.kitchen_speaker | none
        switch.relay_7 | Relay 7 | Off | power | idle | switch.turn_on(switch.relay_7) | - | -
        sensor.relay_7_power | none
        device_tracker.phone | none
        sensor.phone_battery_level | none
        automation.midnight_check | none
        automation.evening_lights | none
        input_datetime.wake_up | none
        lock.blue_door | Blue door | Unlocked | unlock | idle | lock.lock(lock.blue_door) | - | -
        lock.blue_door | Blue door | … | lock | idle | - | - | -
        cover.side_gate | Side gate | Open | generic | active | - | - | -
        cover.side_gate | Side gate | Closed | generic | idle | cover.open_cover(cover.side_gate) | - | confirm
        switch.desk_plug | Desk plug | Unavailable | power | idle | - | - | -
        button.reboot | button.reboot |  | button | idle | - | - | -
        input_boolean.guest_mode | input_boolean.guest_mode | On | generic | active | input_boolean.turn_off(input_boolean.guest_mode) | - | -
        input_select.scene_mode | input_select.scene_mode | Evening | generic | active | - | day/evening | -
        select.preset | select.preset | Unavailable | generic | idle | - | - | -
        """))
    }

    // MARK: - Layouts

    @Test func carLayout() {
        let car = KhalaCarLayout(name: "Rover", members: Screens.car, attributes: Screens.carAttributes)
        #expect(KhalaGolden.matches("car", KhalaGolden.car(car), """
        name: Rover
        battery: 65.0 from sensor.rover_battery_level
        range: ≈ 302 km
        charging: Not charging isCharging=false
        chargeLimit: number.rover_charge_limit Charge limit 80.0 [50.0...100.0 by 1.0] %
        chargeCurrent: number.rover_charge_current Charge current 16.0 [0.0...16.0 by 1.0] A
        tracker: device_tracker.rover_location place=At home
        wake: button.rover_wake connectivity=binary_sensor.rover_status awake=false
        media: media_player.rover_media_player
        inside: 27.4 outside: 26.5
        chargerPower: 0 kW timeToFull: -
        climate: climate.rover_climate on=false current=27.5 onMode=heat_cool target=climate.rover_climate Target 21.0 [15.0...28.0 by 0.5] °
        wakePlan: pressAndWait button.rover_wake binary_sensor.rover_status
        [overview]
        lock.rover_lock | Lock | Locked | lock | active | lock.unlock(lock.rover_lock) | - | confirm
        switch.rover_sentry_mode | Sentry mode | On | shield | active | switch.turn_off(switch.rover_sentry_mode) | - | -
        cover.rover_charge_port_door | Charge port door | Closed | chargePort | idle | cover.open_cover(cover.rover_charge_port_door) | - | confirm
        cover.rover_frunk | Frunk | Closed | frunk | idle | cover.open_cover(cover.rover_frunk) | - | confirm
        cover.rover_trunk | Trunk | Closed | trunk | idle | cover.open_cover(cover.rover_trunk) | - | confirm
        button.rover_flash_lights | Flash lights |  | lights | idle | button.press(button.rover_flash_lights) | - | -
        button.rover_honk_horn | Honk horn |  | horn | idle | button.press(button.rover_honk_horn) | - | -
        [more]
        button.rover_homelink | Homelink |  | button | idle | button.press(button.rover_homelink) | - | -
        button.rover_play_sound | Play sound |  | button | idle | button.press(button.rover_play_sound) | - | -
        [climate]
        switch.rover_auto_seat_climate_left | Auto seat climate left | Off | seat | idle | switch.turn_on(switch.rover_auto_seat_climate_left) | - | -
        select.rover_seat_heater_front_left | Seat heater front left | Off | seat | idle | - | off/low/medium/high | -
        switch.rover_defrost | Defrost | Off | defrost | idle | switch.turn_on(switch.rover_defrost) | - | -
        [charging]
        lock.rover_charge_cable_lock | Charge cable lock | Locked | lock | active | lock.unlock(lock.rover_charge_cable_lock) | - | confirm
        cover.rover_charge_port_door | Charge port door | Closed | chargePort | idle | cover.open_cover(cover.rover_charge_port_door) | - | confirm
        switch.rover_charge | Charge | Off | power | idle | switch.turn_on(switch.rover_charge) | - | -
        """))
    }

    @Test func homeCarLayout() {
        let members = Home.home.filter { $0.deviceId == "dev-rover" }
        let car = KhalaCarLayout(name: "Rover", members: members, attributes: [:])
        #expect(KhalaGolden.matches("car-home", KhalaGolden.car(car), """
        name: Rover
        battery: 72.0 from sensor.rover_battery_level
        range: -
        charging: - isCharging=false
        chargeLimit: -
        chargeCurrent: -
        tracker: device_tracker.rover_location place=Away
        wake: - connectivity=- awake=-
        media: media_player.rover_media
        inside: - outside: -
        chargerPower: - timeToFull: 1792513800.0
        climate: -
        wakePlan: none
        [overview]
        lock.rover_lock | Lock | Locked | lock | active | lock.unlock(lock.rover_lock) | - | confirm
        [more]
        [climate]
        switch.rover_defrost | Defrost | Off | defrost | idle | switch.turn_on(switch.rover_defrost) | - | -
        [charging]
        """))
    }

    @Test func heatLayouts() {
        let tank = Screens.heater.filter { $0.deviceId == "dev-tank" }
        let switcher = KhalaHeatLayout(heater: tank[0], platform: "switcher_kis", members: tank)
        let plain = KhalaHeatLayout(heater: tank[0], platform: nil, members: tank)
        let cellar = KhalaHeatLayout(heater: Kinds.cellarTank, platform: "fake_heater", members: [Kinds.cellarTank])
        let plug = KhalaHeatLayout(heater: Kinds.deskPlug, platform: "switcher_kis", members: [Kinds.deskPlug, Kinds.deskPlugPower])
        let text = [switcher, plain, cellar, plug].map(KhalaGolden.heat).joined(separator: "\n--\n")
        #expect(KhalaGolden.matches("heat", text, """
        heater: switch.tank_9 on=true unavailable=false state=On
        remaining: 1930.0 power: 2.5 kW duration=true
        heat45: switcher_kis.turn_on_with_timer(switch.tank_9){timer_minutes=45}
        off: switch.turn_off(switch.tank_9)
        --
        heater: switch.tank_9 on=true unavailable=false state=On
        remaining: 1930.0 power: 2.5 kW duration=false
        heat45: switch.turn_on(switch.tank_9)
        off: switch.turn_off(switch.tank_9)
        --
        heater: water_heater.cellar_tank on=true unavailable=false state=52°
        remaining: - power: - duration=false
        heat45: water_heater.turn_on(water_heater.cellar_tank)
        off: water_heater.turn_off(water_heater.cellar_tank)
        --
        heater: switch.desk_plug on=true unavailable=false state=On
        remaining: - power: 12.5 W duration=true
        heat45: switcher_kis.turn_on_with_timer(switch.desk_plug){timer_minutes=45}
        off: switch.turn_off(switch.desk_plug)
        """))
    }

    @Test func mediaLayouts() {
        let receiver = KhalaMediaLayout(entity: Screens.receiver, attributes: Screens.receiverAttributes, name: "Den")
        let carPlayer = Screens.car.first { $0.domain == "media_player" }!
        let car = KhalaMediaLayout(entity: carPlayer, attributes: Screens.carAttributes[carPlayer.entityId]
            ?? ["supported_features": 16437, "volume_level": 0.25])
        let speaker = KhalaMediaLayout(entity: Home.home.first { $0.entityId == "media_player.kitchen_speaker" }!,
                                       attributes: ["supported_features": 4 | 128 | 256, "volume_level": 0.3,
                                                    "source": "Radio"])
        let off = KhalaMediaLayout(entity: Home.home.first { $0.entityId == "media_player.den_zone_2" }!,
                                   attributes: ["supported_features": 69004])
        let text = [receiver, car, speaker, off].map(KhalaGolden.media).joined(separator: "\n--\n")
        #expect(KhalaGolden.matches("media", text, """
        player: media_player.den_receiver name=Den on=true unavailable=false
        line: On · Music power=true volume=0.455 muted=false
        sources: Bluetooth/Music/Console source=Music
        modes: MUSIC/MOVIE/STEREO mode=STEREO receiver=true
        --
        player: media_player.rover_media_player name=Rover Media player on=true unavailable=false
        line: Paused power=false volume=0.25 muted=false
        sources:  source=-
        modes:  mode=- receiver=false
        --
        player: media_player.kitchen_speaker name=Kitchen on=true unavailable=false
        line: Playing · Radio power=true volume=0.3 muted=false
        sources:  source=Radio
        modes:  mode=- receiver=false
        --
        player: media_player.den_zone_2 name=Den Zone 2 on=false unavailable=false
        line: Off power=true volume=- muted=false
        sources:  source=-
        modes:  mode=- receiver=false
        """))
    }
}
