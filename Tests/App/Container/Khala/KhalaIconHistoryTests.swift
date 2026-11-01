import Foundation
@testable import HomeAssistant
import Testing

/// Slice 6: the icon chain (decision 4: SF Symbols first, HA's own icon as the fallback, then the domain default)
/// and the one `KhalaHistoryRequest` behind camera events, car presence and boiler runs.
struct KhalaIconHistoryTests {
    private typealias Fixtures = KhalaTestFixtures
    private typealias Kinds = KhalaKindFixtures
    private typealias Screens = KhalaScreenFixtures

    private static func text(_ glyph: KhalaGlyph) -> String {
        switch glyph {
        case let .sf(name): return "sf " + name
        case let .mdi(name): return "mdi " + name
        }
    }

    /// An entity as the app builds it, with HA's own resolved icon.
    private static func entity(
        _ id: String,
        _ state: String,
        _ attributes: [String: Any] = [:],
        resolved: String? = nil,
        platform: String? = nil,
        translationKey: String? = nil
    ) -> KhalaEntity {
        KhalaEntity(entityId: id, state: state, lastChanged: Fixtures.now, attributes: attributes,
                    platform: platform, translationKey: translationKey, resolvedIcon: resolved)
    }

    // MARK: - Devices

    /// Every device of the synthetic homes, as the menu and the Now card draw it, recorded in slice 6. Without
    /// HA's icon map (as here) switches fall to their domain default and the vacuum to HA's own MDI glyph, since SF
    /// has none. What changed against slice 5 is pinned down by `onlyCoversAndPinsWithTheOtherRoleChanged`.
    @Test func everyDeviceGetsAGlyph() {
        let detected = KhalaDeviceCatalog.build(entities: Kinds.everything + Fixtures.home, assignments: [])
        let pinned = KhalaDeviceCatalog.build(entities: KhalaGoldenTests.pinnedHome, assignments: KhalaGoldenTests.pins)
            .filter(\.isPinned)
        let lines = (detected + pinned).map { "\($0.id) \($0.kind) -> \(Self.text($0.glyph))" }
        #expect(KhalaGolden.matches("device-glyphs", lines.joined(separator: "\n"), """
        dev-rover car -> sf car
        dev-cellar water_heater -> sf drop
        dev-loft climate -> sf thermometer.medium
        dev-ac climate -> sf thermometer.medium
        dev-den media -> sf tv
        dev-kitchen media -> sf tv
        dev-blue lock -> sf lock
        dev-shed cover -> sf door.garage.open
        dev-gate cover -> mdi mdi:gate
        dev-fan fan -> sf fanblades
        dev-plug switch -> sf powerplug
        entity:switch.other switch -> sf powerplug
        dev-relay switch -> sf powerplug
        dev-tank switch -> sf powerplug
        entity:light.lounge_lights light_group -> sf lightbulb.2
        dev-lamp light -> sf lightbulb
        dev-bulb light -> sf lightbulb
        pin:switch.relay_7 water_heater -> sf drop
        pin:light.desk_lamp switch -> sf lightbulb
        pin:lock.blue_door lock -> sf lock
        pin:camera.porch camera -> sf video
        pin:climate.study_ac water_heater -> sf drop
        pin:media_player.kitchen_speaker media -> sf tv
        pin:device_tracker.phone car -> sf car
        pin:vacuum.dust_bot switch -> mdi mdi:robot-vacuum
        pin:light.lounge_lights switch -> sf lightbulb
        pin:event.yard_field_detection camera -> sf video
        """))
    }

    /// Slice 5's rule (`KhalaTheme.symbol(device)`): the descriptor's symbol for lights, fans, climate, covers and
    /// locks, the colour family's for the rest.
    private static func slice5Symbol(_ device: KhalaDevice) -> String {
        switch device.kind {
        case .light, .lightGroup, .fan, .climate, .cover, .lock: return device.kind.descriptor.fallbackSymbol
        default: break
        }
        switch device.accent {
        case .security: return "video"
        case .car: return "car"
        case .heat: return "drop"
        case .media: return "tv"
        case .sun: return "sun.max.fill"
        case .neutral: return "powerplug"
        }
    }

    /// The only devices whose glyph changed: the garage and the gate (slice 4 drew every cover as blinds), and
    /// three things pinned with the legacy "Other" role (kind `switch`), which all showed a plug: two lights, now
    /// bulbs, and a vacuum, now HA's robot vacuum.
    @Test func onlyCoversAndPinsWithTheOtherRoleChanged() {
        let detected = KhalaDeviceCatalog.build(entities: Kinds.everything + Fixtures.home, assignments: [])
        let pinned = KhalaDeviceCatalog.build(entities: KhalaGoldenTests.pinnedHome, assignments: KhalaGoldenTests.pins)
        let changed = (detected + pinned)
            .filter { $0.glyph != .sf(Self.slice5Symbol($0)) }
            .map { "\($0.id): \(Self.slice5Symbol($0)) -> \(Self.text($0.glyph))" }
        #expect(Set(changed) == [
            "dev-shed: blinds.horizontal.closed -> sf door.garage.open",
            "dev-gate: blinds.horizontal.closed -> mdi mdi:gate",
            "pin:light.desk_lamp: powerplug -> sf lightbulb",
            "pin:light.lounge_lights: powerplug -> sf lightbulb",
            "pin:vacuum.dust_bot: powerplug -> mdi mdi:robot-vacuum",
        ])
    }

    /// The kinds 41.1 already drew keep their glyph in the menu and on the chips: car, hot water, media and camera
    /// by their colour family's, lights, fans, climate and a locked lock by their descriptor's.
    @Test func designedKindsKeepTheGlyphTheyHad() {
        let face = Self.entity("sensor.any", "1", resolved: "mdi:battery-70")
        let expected: [(KhalaKind, String)] = [
            (.car, "car"), (.waterHeater, "drop"), (.media, "tv"), (.camera, "video"), (.light, "lightbulb"),
            (.lightGroup, "lightbulb.2"), (.fan, "fanblades"), (.climate, "thermometer.medium"),
        ]
        for (kind, symbol) in expected {
            #expect(KhalaIconChain.device(kind: kind, face: face) == .sf(symbol), "\(kind)")
        }
        #expect(KhalaIconChain.device(kind: .lock, face: Self.entity("lock.a", "locked")) == .sf("lock"))
        #expect(KhalaIconChain.device(kind: .lock, face: Self.entity("lock.a", "unlocked")) == .sf("lock.open"))
    }

    /// Slice 4 drew every cover as blinds in the menu: a garage, a door and a window now look like one, open or
    /// closed. A gate has no SF Symbol, so HA's own gate is drawn: the one HA resolved, else HA's default.
    @Test func coversLookLikeWhatTheyAre() {
        func glyph(_ deviceClass: String?, _ state: String, resolved: String? = nil) -> KhalaGlyph {
            let attributes: [String: Any] = deviceClass.map { ["device_class": $0] } ?? [:]
            return KhalaIconChain.device(kind: .cover, face: Self.entity("cover.x", state, attributes, resolved: resolved))
        }
        #expect(glyph("garage", "closed") == .sf("door.garage.closed"))
        #expect(glyph("garage", "open") == .sf("door.garage.open"))
        #expect(glyph("garage", "closing") == .sf("door.garage.open"))
        #expect(glyph("door", "closed") == .sf("door.left.hand.closed"))
        #expect(glyph("door", "open") == .sf("door.left.hand.open"))
        #expect(glyph("window", "open") == .sf("window.vertical.open"))
        #expect(glyph("gate", "closed") == .mdi("mdi:gate"))
        #expect(glyph("gate", "open") == .mdi("mdi:gate-open"))
        #expect(glyph("gate", "open", resolved: "mdi:gate-arrow-right") == .mdi("mdi:gate-arrow-right"))
        // A cover that doesn't say what it is: HA's icon (SF when one means the same), else blinds.
        #expect(glyph(nil, "closed", resolved: "mdi:window-shutter") == .sf("window.shade.closed"))
        #expect(glyph(nil, "closed") == .sf("blinds.horizontal.closed"))
        // The cover screen's main control draws the same glyph as the menu.
        let gate = Kinds.sideGate
        let panel = KhalaCoverPanel(entity: gate, attributes: Kinds.attributes[gate.entityId] ?? [:])
        #expect(panel.controls[0].symbol == KhalaIconChain.device(kind: .cover, face: gate))
    }

    /// The order: Khala's SF Symbol first, then HA's icon (as an SF Symbol of the same meaning when there is one,
    /// else as MDI), then the domain default. A registry icon the user set counts as HA's icon.
    @Test func sfFirstThenHAThenDomainDefault() {
        // Khala's designed glyph beats HA's icon.
        #expect(KhalaIconChain.device(kind: .light, face: Self.entity("light.a", "on", resolved: "mdi:ceiling-light"))
            == .sf("lightbulb"))
        // A switch has no designed glyph: HA's icon, mapped to SF…
        #expect(KhalaIconChain.device(kind: .switch, face: Self.entity("switch.a", "on", resolved: "mdi:power-plug"))
            == .sf("powerplug"))
        #expect(KhalaIconChain.device(kind: .switch, face: Self.entity("switch.a", "on", ["icon": "mdi:water-boiler"],
                                                                        resolved: "mdi:toggle-switch-variant"))
            == .sf("drop"))
        // …or drawn as MDI when SF has nothing of the same meaning…
        #expect(KhalaIconChain.device(kind: .switch, face: Self.entity("switch.a", "on", ["icon": "mdi:robot"]))
            == .mdi("mdi:robot"))
        #expect(KhalaIconChain.device(kind: .generic, face: Self.entity("switch.a", "on", ["icon": "robot"]))
            == .mdi("mdi:robot"))
        // …and with no icon at all, the domain default, else the kind's fallback.
        #expect(KhalaIconChain.device(kind: .switch, face: Self.entity("switch.a", "on")) == .sf("powerplug"))
        #expect(KhalaIconChain.device(kind: .generic, face: Self.entity("input_boolean.a", "on")) == .sf("switch.2"))
        #expect(KhalaIconChain.device(kind: .generic, face: Self.entity("sensor.a", "1")) == .sf("powerplug"))
        #expect(KhalaIconChain.device(kind: .generic, face: nil) == .sf("powerplug"))
    }

    // MARK: - Tiles

    /// The car's and the boiler's tiles: a hint's glyph always wins, whatever HA's icon says; a tile Khala only
    /// has the generic glyph for takes HA's icon.
    @Test func hintGlyphsKeepWinningOnTheCarAndTheBoiler() {
        let attributes = Kinds.everythingAttributes
        var checked = 0
        for base in Screens.car + Screens.heater {
            let entity = Self.entity(base.entityId, base.state, attributes[base.entityId] ?? [:],
                                     resolved: "mdi:robot", platform: base.platform,
                                     translationKey: base.translationKey)
            guard let control = KhalaControl.make(entity, attributes: attributes[base.entityId] ?? [:]) else {
                continue
            }
            let glyph = KhalaIconChain.tile(control, entity: entity)
            if control.glyph == .generic {
                #expect(glyph == .mdi("mdi:robot"), "\(entity.entityId)")
            } else {
                #expect(glyph == .sf(control.glyph.symbolName), "\(entity.entityId)")
                checked += 1
            }
        }
        #expect(checked >= 10)
        // Without HA's icon a tile draws exactly what 41.1 drew.
        for base in Screens.car + Screens.heater {
            guard let control = KhalaControl.make(base, attributes: attributes[base.entityId] ?? [:]) else { continue }
            #expect(KhalaIconChain.tile(control, entity: base) == .sf(control.glyph.symbolName)
                || base.domain == "cover", "\(base.entityId)")
        }
    }

    @Test func aGarageTileIsAGarage() throws {
        let shed = Kinds.shedDoor
        let control = try #require(KhalaControl.make(shed, attributes: Kinds.attributes[shed.entityId] ?? [:]))
        #expect(control.glyph == .generic)
        #expect(KhalaIconChain.tile(control, entity: shed) == .sf("door.garage.open"))
    }

    // MARK: - MDI table

    @Test func theTableMapsMeaningAndLeavesTheRestToHA() {
        #expect(KhalaMDISymbols.sfSymbol(forMDI: "mdi:garage-open") == "door.garage.open")
        #expect(KhalaMDISymbols.sfSymbol(forMDI: "garage") == "door.garage.closed")
        #expect(KhalaMDISymbols.sfSymbol(forMDI: "mdi:battery-70") == "battery.75")
        #expect(KhalaMDISymbols.sfSymbol(forMDI: "mdi:battery-10") == "battery.0")
        #expect(KhalaMDISymbols.sfSymbol(forMDI: "mdi:battery-unknown") == nil)
        for unmapped in ["mdi:gate", "mdi:gate-open", "mdi:robot-vacuum", "mdi:robot"] {
            #expect(KhalaMDISymbols.sfSymbol(forMDI: unmapped) == nil, "\(unmapped)")
        }
        // Keys are bare MDI names; values are SF names, never MDI ones.
        #expect(KhalaMDISymbols.table.keys.allSatisfy { !$0.hasPrefix("mdi:") && !$0.contains(".") })
        #expect(KhalaMDISymbols.table.values.allSatisfy { !$0.contains(":") && !$0.contains("-") })
    }

    // MARK: - History

    /// What the screens sent before slice 6, per screen: the same entities and window, every change, the state
    /// at the start. Arrivals and on-runs no longer ask for attributes (they never read them).
    @Test func eachScreenAsksForWhatItAskedBefore() {
        let now = Fixtures.now
        let format = ISO8601DateFormatter()
        let camera = KhalaHistoryRequest.cameraEvents(["event.porch_field_detection", "event.porch_line_crossing"])
        let car = KhalaHistoryRequest.presence(of: "device_tracker.rover_location")
        let boiler = KhalaHistoryRequest.runs(of: "switch.tank_9")
        for (request, days, ids, attributes) in [
            (camera, 7.0, ["event.porch_field_detection", "event.porch_line_crossing"], true),
            (car, 3.0, ["device_tracker.rover_location"], false),
            (boiler, 7.0, ["switch.tank_9"], false),
        ] {
            let message = request.message(now: now)
            #expect(message["start_time"] as? String == format.string(from: now.addingTimeInterval(-days * 86400)))
            #expect(message["entity_ids"] as? [String] == ids)
            #expect(message["include_start_time_state"] as? Bool == true)
            #expect(message["significant_changes_only"] as? Bool == false)
            #expect(message["minimal_response"] as? Bool == false)
            #expect(message["no_attributes"] as? Bool == !attributes)
        }
        #expect(KhalaHistoryRequest.cameraEventsWindow == 7 * 86400)
    }

    /// A synthetic recorder answer, as `history/history_during_period` sends it.
    private static func answer(attributes: Bool) -> [String: Any] {
        let t0 = Fixtures.now.timeIntervalSince1970
        func row(_ state: String, _ minutes: Double, _ attrs: [String: Any]? = nil) -> [String: Any] {
            var row: [String: Any] = ["s": state, "lu": t0 + minutes * 60]
            if attributes, let attrs { row["a"] = attrs }
            return row
        }
        return [
            "event.porch_field_detection": [
                row("2026-10-20T04:10:00.000+00:00", -470, ["event_type": "vehicle"]),
                row("2026-10-20T07:35:02.953+00:00", -265, ["event_type": "human"]),
                row("2026-10-16T07:35:02.953+00:00", -6000, ["event_type": "human"]),
            ],
            "device_tracker.rover_location": [
                row("home", -4000, ["latitude": 1.0]), row("not_home", -3000), row("not_home", -2990),
                row("Work", -2000), row("not_home", -1500), row("unknown", -1200), row("home", -900),
                row("not_home", -300), row("home", -60),
            ],
            "switch.tank_9": [
                row("off", -3000), row("on", -2900), row("off", -2855), row("unavailable", -1000), row("on", -20),
            ],
        ]
    }

    /// The car's presence, the boiler's runs and the camera's detections come out exactly as the old per-screen
    /// code made them, with and without attributes in the answer.
    @Test func theScreensShowWhatTheyShowedBefore() {
        let now = Fixtures.now
        let full = KhalaHistory.parse(Self.answer(attributes: true))
        // The old car screen: `presenceChanges(history[tracker]).prefix(4)`.
        let tracker = "device_tracker.rover_location"
        let oldPresence = Array(KhalaHistory.presenceChanges(full[tracker] ?? []).prefix(4))
        // The old hot-water screen: `runs(history[primary], now:)`.
        let oldRuns = KhalaHistory.runs(full["switch.tank_9"] ?? [], now: now)
        // The old camera screen: `detections(…, history:, since: now − 7 days)`.
        let porch = Fixtures.home.first { $0.entityId == "camera.porch" }!
        let oldWeek = KhalaCameraCatalog.detections(for: porch, in: Fixtures.home, history: full,
                                                    since: now.addingTimeInterval(-7 * 86400), now: now)
        #expect(oldPresence.count == 4)
        #expect(oldRuns.count == 2)
        #expect(oldWeek.count == 3)

        let car = KhalaHistoryRequest.presence(of: tracker)
        let boiler = KhalaHistoryRequest.runs(of: "switch.tank_9")
        let camera = KhalaHistoryRequest.cameraEvents(
            KhalaCameraCatalog.eventEntities(for: porch, in: Fixtures.home).map(\.entityId)
        )
        for withAttributes in [true, false] {
            let states = car.states(from: Self.answer(attributes: withAttributes))
            #expect(car.presenceChanges(from: states) == oldPresence)
            #expect(boiler.runs(from: states, now: now) == oldRuns)
        }
        let events = camera.states(from: Self.answer(attributes: true))
        let week = KhalaCameraCatalog.detections(for: porch, in: Fixtures.home, history: events,
                                                 since: camera.start(now: now), now: now)
        #expect(week == oldWeek)
        #expect(week.map(\.noun) == oldWeek.map(\.noun))
    }
}
