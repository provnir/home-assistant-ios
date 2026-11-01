import Foundation
@testable import HomeAssistant
import Testing

/// Slice 5: the hints file, the screens that read it (car, hot water), the routing table and "Show as…", and the
/// source scans that keep word matching and integration names out of Swift.
struct KhalaHintsTests {
    private typealias Tesla = KhalaTeslaFleetFixture
    private typealias Screens = KhalaScreenFixtures

    // MARK: - The file

    @Test func theHintsFileShipsAndDecodes() throws {
        let hints = KhalaHints.builtIn
        #expect(hints.entries.count >= 30)
        // Both integrations Nir's daily screens read are in it, as data.
        #expect(hints.hint(platform: "tesla_fleet", domain: "button", translationKey: "wake")?.role == .wake)
        let timer = try #require(hints.hint(platform: "switcher_kis", domain: "switch", translationKey: nil)?.timedOn)
        #expect(timer == KhalaTimedOn(domain: "switcher_kis", service: "turn_on_with_timer", field: "timer_minutes",
                                      unit: "min"))
        // Every entry is keyed, and every role, section and glyph it names is one this build knows.
        let raw = try JSONSerialization.jsonObject(with: Self.hintsFileData()) as? [String: Any]
        let entries = try #require(raw?["hints"] as? [[String: Any]])
        #expect(entries.count == hints.entries.count)
        for (entry, hint) in zip(entries, hints.entries) {
            #expect(!hint.platform.isEmpty)
            #expect((entry["role"] == nil) == (hint.role == nil), "role in \(entry)")
            #expect(hint.role != .unknown, "unknown role in \(entry)")
            #expect((entry["glyph"] == nil) == (hint.glyph == nil), "unknown glyph in \(entry)")
            #expect((entry["section"] == nil) == hint.sections.isEmpty, "unknown section in \(entry)")
        }
    }

    @Test func theHintsFileHoldsIntegrationKnowledgeOnly() throws {
        let raw = try JSONSerialization.jsonObject(with: Self.hintsFileData()) as? [String: Any]
        let entries = try #require(raw?["hints"] as? [[String: Any]])
        let allowed: Set<String> = ["platform", "domain", "translation_key", "role", "section", "glyph", "timedOn"]
        for entry in entries {
            // No entity ids, names, device ids or areas: nothing that belongs to one home.
            #expect(Set(entry.keys).isSubset(of: allowed), "unexpected key in \(entry)")
            for value in entry.values.compactMap({ $0 as? String }) {
                #expect(!value.contains("."), "\(value) looks like an entity id")
            }
        }
    }

    @Test func theMostSpecificHintWinsAndUnknownPartsAreSkipped() throws {
        let json = """
        {"version": 1, "hints": [
          {"platform": "acme", "glyph": "power"},
          {"platform": "acme", "domain": "switch", "section": "charging",
           "timedOn": {"service": "boost_for", "field": "seconds", "unit": "s"}},
          {"platform": "acme", "domain": "switch", "translation_key": "boost", "section": ["overview", "climate"],
           "glyph": "seat", "role": "from_the_future"},
          {"platform": "acme", "domain": "sensor", "translation_key": "boost", "role": "battery", "glyph": "laser"}
        ]}
        """
        let hints = try KhalaHints.decode(Data(json.utf8))
        let boost = try #require(hints.hint(platform: "acme", domain: "switch", translationKey: "boost"))
        #expect(boost.sections == [.overview, .climate])
        #expect(boost.glyph == .seat)
        #expect(boost.role == .unknown)
        let sensor = try #require(hints.hint(platform: "acme", domain: "sensor", translationKey: "boost"))
        #expect(sensor.role == .battery)
        #expect(sensor.glyph == nil)
        // Another key on the same domain: the domain-wide entry.
        #expect(hints.hint(platform: "acme", domain: "switch", translationKey: "other")?.sections == [.charging])
        #expect(hints.hint(platform: "acme", domain: "light", translationKey: nil)?.glyph == .power)
        #expect(hints.hint(platform: "other", domain: "switch", translationKey: "boost") == nil)
        // A timer in seconds sends seconds.
        let plug = Screens.entity("switch.plug", "off", device: "dev-plug", platform: "acme")
        let heat = KhalaHeatLayout(heater: plug, platform: "acme", members: [plug], hints: hints)
        #expect(KhalaGolden.call(heat.heatCall(minutes: 30)) == "acme.boost_for(switch.plug){seconds=1800}")
    }

    // MARK: - Car

    @Test func aKnownCarKeepsItsThreeTabs() {
        let car = KhalaCarLayout(name: "Vega", members: Tesla.vehicle, attributes: Tesla.attributes)
        #expect(car.tabs == [.overview, .climate, .charging])
        let rover = KhalaCarLayout(name: "Rover", members: Screens.car, attributes: Screens.carAttributes)
        #expect(rover.tabs == [.overview, .climate, .charging])
    }

    @Test func aCarWithoutHintsGetsPlainGenericTabs() {
        // The same car with no registry facts: every name still carries the words 41.1 read ("wake", "range",
        // "seat", "charge"...), and none of them is used.
        let car = KhalaCarLayout(name: "Vega", members: Tesla.unhinted, attributes: Tesla.attributes)
        #expect(car.wakeButtonId == nil)
        #expect(car.connectivityId == nil)
        #expect(car.wakePlan == .none)
        #expect(car.rangeText == nil)
        #expect(car.chargingText == nil)
        #expect(car.chargerPowerText == nil)
        #expect(car.timeToFull == nil)
        #expect(car.insideTemperature == nil && car.outsideTemperature == nil)
        // What domain and device class say on their own still shows.
        #expect(car.battery == 64)
        #expect(car.batteryEntityId == "sensor.vega_battery_level")
        #expect(car.chargeLimit?.entityId == "number.vega_charge_limit")
        #expect(car.chargeCurrent?.entityId == "number.vega_charge_current")
        #expect(car.tracker?.entityId == "device_tracker.vega_location")
        #expect(car.mediaPlayerId == "media_player.vega_media_player")
        #expect(car.climate?.entityId == "climate.vega_cabin_overheat_protection")
        // Every control on Overview, glyph-less buttons under More; nothing sorted by words.
        #expect(car.climateControls.isEmpty)
        #expect(car.chargingControls.isEmpty)
        #expect(car.moreControls.map(\.entityId) == [
            "button.vega_flash_lights", "button.vega_homelink", "button.vega_honk_horn", "button.vega_keyless_driving",
            "button.vega_play_fart", "button.vega_wake",
        ])
        #expect(car.overview.count == 22)
        #expect(Set(car.overview.map(\.glyph)).isSubset(of: [.lock, .unlock, .window, .power, .generic]))
        #expect(car.tabs == [.overview, .climate, .charging])
        // The same through an empty hints table.
        let noHints = KhalaCarLayout(name: "Vega", members: Tesla.vehicle, attributes: Tesla.attributes, hints: .empty)
        #expect(KhalaGolden.car(noHints) == KhalaGolden.car(car))
    }

    @Test func aBareCarHasOneTabAndNoBar() {
        let members = [
            Screens.entity("device_tracker.van", "home", device: "dev-van", deviceName: "Van"),
            Screens.entity("lock.van", "locked", device: "dev-van", deviceName: "Van"),
            Screens.entity("sensor.van_battery", "51", ["device_class": "battery", "unit_of_measurement": "%"],
                           device: "dev-van", deviceName: "Van"),
        ]
        let car = KhalaCarLayout(name: "Van", members: members, attributes: [:])
        #expect(car.tabs == [.overview])
        #expect(car.battery == 51)
        #expect(car.overview.map(\.entityId) == ["lock.van"])
        #expect(car.wakePlan == .none)
    }

    // MARK: - Hot water

    @Test func theBoilerTimerIsTheHintsAndNothingElse() {
        let tank = Screens.heater.filter { $0.deviceId == "dev-tank" }
        let switcher = KhalaHeatLayout(heater: tank[0], platform: "switcher_kis", members: tank)
        #expect(KhalaHeatLayout.durations == [30, 45, 60, 90])
        for minutes in KhalaHeatLayout.durations {
            #expect(KhalaGolden.call(switcher.heatCall(minutes: minutes))
                == "switcher_kis.turn_on_with_timer(switch.tank_9){timer_minutes=\(minutes)}")
        }
        // Without the hints: a plain switch, no timer, no remaining time.
        let bare = KhalaHeatLayout(heater: tank[0], platform: "switcher_kis", members: tank, hints: .empty)
        #expect(!bare.supportsDuration)
        #expect(bare.remaining == nil)
        #expect(KhalaGolden.call(bare.heatCall(minutes: 45)) == "switch.turn_on(switch.tank_9)")
        // A sensor called "remaining" but not hinted is not the timer.
        let renamed = tank.map { entity in
            entity.domain == "sensor" && entity.deviceClass == nil
                ? Screens.entity(entity.entityId, entity.state, ["friendly_name": "Tank 9 Remaining time"],
                                 device: "dev-tank", deviceName: "Tank 9")
                : entity
        }
        #expect(KhalaHeatLayout(heater: tank[0], platform: "switcher_kis", members: renamed).remaining == nil)
    }

    // MARK: - Routing table and "Show as…"

    @Test func theRoutingTableHasOneRoutePerKind() {
        let routes = Dictionary(uniqueKeysWithValues: KhalaDescriptors.all.map { ($0.kind, $0.route) })
        #expect(routes[.car] == .car)
        #expect(routes[.waterHeater] == .water)
        #expect(routes[.media] == .mediaSheet)
        #expect(routes[.camera] == .camera)
        #expect(routes[.lock] == .camera)
        for kind in [KhalaKind.climate, .vacuum, .cover, .fan, .lightGroup, .light, .switch, .generic] {
            #expect(routes[kind] == .template, "\(kind)")
        }
        #expect(KhalaKind(rawValue: "from_the_future").descriptor.route == .template)
    }

    @Test func showAsPicksTheScreenAndKeepsTheColour() {
        let relay = KhalaTestFixtures.home.filter { $0.deviceId == "dev-relay" }
        var pin = KhalaRoleAssignment(entityId: "switch.relay_7", role: .neutral, label: "Kettle")
        #expect(pin.showAs == .switch)
        func route(_ pin: KhalaRoleAssignment) -> String {
            let devices = KhalaDeviceCatalog.build(entities: relay, assignments: [pin])
            return KhalaGolden.route(KhalaRouting.target(for: devices[0], cameras: []))
                + " \(devices[0].kind.descriptor.route) \(devices[0].accent.rawValue)"
        }
        #expect(route(pin) == "screen device(pin:switch.relay_7) template neutral")
        pin.showAs = .waterHeater
        #expect(pin.role == .neutral)
        #expect(route(pin) == "screen device(pin:switch.relay_7) water neutral")
        pin.showAs = .media
        #expect(route(pin) == "sheet pin:switch.relay_7 switch.relay_7 mediaSheet neutral")
        pin.showAs = .car
        #expect(route(pin) == "screen device(pin:switch.relay_7) car neutral")
        // Picking the role afterwards still picks that role's screen too, as the picker always has.
        pin.role = .heat
        #expect(pin.showAs == .waterHeater)
        pin.showAs = .switch
        #expect(pin.role == .heat)
        #expect(route(pin) == "screen device(pin:switch.relay_7) template heat")
        // It is stored like any pin: an older build still reads its role.
        let data = try? JSONEncoder().encode([pin])
        let stored = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }
        #expect(stored?.first?["role"] as? String == "heat")
        #expect(stored?.first?["kind"] as? String == "switch")
        #expect(data.flatMap { try? JSONDecoder().decode([KhalaRoleAssignment].self, from: $0) } == [pin])
    }

    @Test func aClimatePinnedAsHeatStillOpensTheWaterScreen() {
        let pin = KhalaRoleAssignment(entityId: "climate.study_ac", role: .heat, label: nil)
        #expect(pin.kind == .waterHeater)
        let devices = KhalaDeviceCatalog.build(entities: KhalaKindFixtures.all, assignments: [pin])
        #expect(devices.first?.kind.descriptor.route == .water)
        // Detected, the same climate is a climate and gets its template.
        let detected = KhalaDeviceCatalog.build(entities: KhalaKindFixtures.all, assignments: [])
        #expect(detected.first { $0.primaryEntityId == "climate.study_ac" }?.kind.descriptor.route == .template)
    }

    @Test func thePickerAlwaysShowsThePinsKind() {
        #expect(KhalaKind.showAsChoices.first == .car)
        #expect(KhalaKind.showAsChoices(including: .light) == KhalaKind.showAsChoices)
        #expect(KhalaKind.showAsChoices(including: .lightGroup).last == .lightGroup)
        #expect(Set(KhalaKind.showAsChoices.map(\.displayName)).count == KhalaKind.showAsChoices.count)
        #expect(KhalaKind.showAsChoices.allSatisfy { $0.isKnown })
    }

    // MARK: - Source scans

    /// The lines of Model allowed to read names, each for a reason that is not word matching, except the first.
    /// Each must still be there (a stale allowance fails), so one is removed the day it isn't needed.
    private static let nameReadingAllowed: [(file: String, fragment: String, reason: String)] = [
        // Word matching, kept: the camera's Mute action turns off a notification switch on the camera's device.
        // Home Assistant gives such a switch no device class and no translation key shared across camera
        // integrations, so there is nothing language-free to match; without the words, Mute would disappear.
        ("Model/KhalaCameraCatalog.swift", #"(entity.entityId + " " + entity.name).lowercased()"#, "camera mute"),
        ("Model/KhalaCameraCatalog.swift", #"["notif", "push", "alert"].contains { text.contains($0) }"#,
         "camera mute"),
        // Name structure, not words: without registry data, an event entity belongs to the camera whose name starts
        // its own ("Porch" + " Field detection"), the way Home Assistant composes entity names.
        ("Model/KhalaCameraCatalog.swift", #"event.name.hasPrefix(camera.name + " ")"#, "registry-less pairing"),
        ("Model/KhalaRouting.swift", #"event.name.hasPrefix($0.name + " ")"#, "registry-less pairing"),
        ("Model/KhalaEntity.swift", "name.hasPrefix(deviceName)", "the entity name without its device's"),
        // Search: what the user typed, matched against what the user sees.
        ("Model/KhalaMenuSection.swift", "$0.name.localizedCaseInsensitiveContains(query)", "menu search"),
        ("Model/KhalaDashboard.swift", "$0.title.localizedCaseInsensitiveContains(query)", "dashboard search"),
    ]

    /// No word matching on names or ids anywhere in Model (DESCRIPTORS-DESIGN.md §4 row 7): every file is scanned,
    /// and only the lines in `nameReadingAllowed` may read a name.
    @Test func modelDoesNoWordMatchingOnNames() {
        let files = Self.sources(in: ["Model"])
        guard files.count > 80 else {
            Issue.record("Khala sources not found under \(Self.sourceRoot.path)")
            return
        }
        var offenders: [String] = []
        var used = Set<Int>()
        for file in files {
            for (number, line) in file.text.components(separatedBy: "\n").enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") { continue }
                guard Self.flagged(code) else { continue }
                if let allowed = Self.nameReadingAllowed.indices.first(where: {
                    Self.nameReadingAllowed[$0].file == file.name && code.contains(Self.nameReadingAllowed[$0].fragment)
                }) {
                    used.insert(allowed)
                } else {
                    offenders.append("\(file.name):\(number + 1): \(code)")
                }
            }
        }
        #expect(offenders.isEmpty, "word matching on names:\n\(offenders.joined(separator: "\n"))")
        for (index, allowance) in Self.nameReadingAllowed.enumerated() where !used.contains(index) {
            Issue.record("stale allowance (\(allowance.reason)): \(allowance.file) \(allowance.fragment)")
        }
    }

    /// The scan catches what it is for: 41.1-style rules on names are flagged.
    @Test func theScanFlagsWordMatching() {
        for code in [
            #"entity.name.lowercased().contains("frunk")"#,
            #"entity.entityId.hasSuffix("_seat_heater")"#,
            #"["seat", "wheel"].contains { text.contains($0) }"#,
            #"if has("steering") { return .wheel }"#,
        ] {
            #expect(Self.flagged(code), "\(code)")
        }
        #expect(!Self.flagged(#"entity.domain == "lock""#))
    }

    private static let wordMatching: [NSRegularExpression] = [
        // `has("…")` helpers.
        #"(?<!\.)\bhas\([^)]*""#,
        #"func has\("#,
        // An id glued to a name to search words in.
        #"entityId\s*\+\s*" "\s*\+"#,
        // A name or id searched for a substring, a prefix or a suffix.
        #"\.(name|entityId|friendlyName)(\.lowercased\(\))?\.(contains|range\(of)"#,
        #"\b(name|entityId|friendlyName|deviceName|title)(\.lowercased\(\))?\."#
            + #"(hasPrefix|hasSuffix|contains|range\(of|localizedCaseInsensitiveContains|localizedStandardContains)\("#,
        #"\b(text|name)\([^)]*\)\.contains\("#,
        // A list of words searched for in a text.
        #"\]\.contains\s*\{\s*\w+\.(contains|hasPrefix|hasSuffix)\(\$0\)"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    private static func flagged(_ code: String) -> Bool {
        let range = NSRange(code.startIndex..., in: code)
        return wordMatching.contains { $0.firstMatch(in: code, range: range) != nil }
    }

    @Test func integrationNamesAreDataNotSwift() {
        let files = Self.sources(in: ["Model", "UI"])
        guard files.count > 150 else {
            Issue.record("Khala sources not found under \(Self.sourceRoot.path)")
            return
        }
        for name in ["switcher_kis", "tesla_fleet"] {
            #expect(files.filter { $0.text.contains(name) }.map(\.name).isEmpty, "\(name) in Swift")
            #expect(String(decoding: Self.hintsFileData(), as: UTF8.self).contains(#""\#(name)""#))
        }
    }

    /// Khala's source root: `linux-check.sh` exports it; in Xcode it is five levels above this file.
    private static var sourceRoot: URL {
        if let root = ProcessInfo.processInfo.environment["KHALA_SOURCE_ROOT"] {
            return URL(fileURLWithPath: root)
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func hintsFileData() -> Data {
        let url = sourceRoot.appendingPathComponent("Sources/App/Frontend/Khala/Model/Resources/khala-hints.json")
        return (try? Data(contentsOf: url)) ?? Data()
    }

    private static func sources(in folders: [String]) -> [(name: String, text: String)] {
        let khala = sourceRoot.appendingPathComponent("Sources/App/Frontend/Khala")
        return folders.flatMap { folder -> [(name: String, text: String)] in
            let directory = khala.appendingPathComponent(folder)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return names.filter { $0.hasSuffix(".swift") }.sorted().compactMap { name in
                (try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)).map {
                    (name: "\(folder)/\(name)", text: $0)
                }
            }
        }
    }
}
