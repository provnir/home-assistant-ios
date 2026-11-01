import Foundation
@testable import HomeAssistant
import Shared
import Testing

/// Slice 4's safety net: no route reaches an unlock, a lock's open, or the opening of a garage door, a gate, a door
/// or an unclassed cover without the confirmation step. Checked over the model's whole intent → confirm → call table
/// (`KhalaConfirmGate`, the only door to `KhalaServiceTable`), for every control the screens build — the new heroes,
/// the car's and generic screen's tiles — and for a control that forgot to declare anything. Synthetic fixtures only.
struct KhalaConfirmGateTests {
    private typealias Facts = KhalaControlGridModelTests

    private static func entity(_ id: String, _ state: String, _ attributes: [String: Any]) -> KhalaEntity {
        KhalaEntity(entityId: id, state: state, lastChanged: KhalaTestFixtures.now, attributes: attributes)
    }

    /// Every intent a control can make, and some no screen makes today (toggle, setOn on a lock).
    private static let intents: [KhalaIntent] = [
        .toggle, .setOn(true), .setOn(false), .press, .lock, .unlock, .open,
        .command(.open), .command(.close), .command(.stop), .command(.openTilt), .command(.closeTilt),
        .set(.position, 0), .set(.position, 30), .set(.position, 60), .set(.position, 100), .set(.tilt, 50),
    ]

    private struct Case {
        let entity: KhalaEntity
        let attributes: [String: Any]
    }

    /// Locks in every state, with and without the open feature; covers of every guarded class (and one with no
    /// class) at closed / half / open / unknown positions.
    private static var dangerous: [Case] {
        var cases: [Case] = []
        for state in ["locked", "unlocked", "jammed", "locking", "unknown", "open"] {
            for features in [0, 1] {
                let attributes: [String: Any] = ["supported_features": features]
                cases.append(Case(entity: entity("lock.front", state, attributes), attributes: attributes))
            }
        }
        for deviceClass in ["garage", "gate", "door", nil] as [String?] {
            for (state, position) in [("closed", 0), ("open", 50), ("open", 100), ("closed", nil)] as [(String, Int?)] {
                var attributes: [String: Any] = ["supported_features": 255]
                if let deviceClass { attributes["device_class"] = deviceClass }
                if let position { attributes["current_position"] = position }
                cases.append(Case(entity: entity("cover.way_in", state, attributes), attributes: attributes))
            }
        }
        return cases
    }

    /// Every control a screen builds for `entity`: its hero, its tile (car / generic), and a bare one that declares
    /// no confirmation at all.
    private static func controls(_ item: Case) -> [KhalaControlModel] {
        var controls: [KhalaControlModel] = []
        switch item.entity.domain {
        case "lock": controls += KhalaLockPanel(entity: item.entity, attributes: item.attributes).controls
        case "cover": controls += KhalaCoverPanel(entity: item.entity, attributes: item.attributes).controls
        default: break
        }
        if let tile = KhalaControl.make(item.entity, attributes: item.attributes) {
            controls.append(KhalaControlModel(tile, entity: item.entity, attributes: item.attributes))
        }
        controls.append(KhalaControlModel(entityId: item.entity.entityId, title: "Bare", symbol: .sf("questionmark"),
                                          kind: .press, confirm: nil))
        return controls
    }

    /// Whether `call` unlocks, opens a lock or opens the guarded cover in `item`.
    private static func isDangerous(_ call: KhalaServiceCall, _ item: Case) -> Bool {
        switch (call.domain, call.service) {
        case ("lock", "unlock"), ("lock", "open"), ("cover", "open_cover"): return true
        case ("cover", "set_cover_position"):
            guard let target = call.data["position"] as? Int else { return true }
            guard let current = KhalaValue.double(item.attributes["current_position"]) else { return true }
            return Double(target) > current
        default: return false
        }
    }

    @Test func nothingDangerousGoesOutUnconfirmed() {
        var dangerousSeen = 0
        for item in Self.dangerous {
            for control in Self.controls(item) {
                for intent in Self.intents {
                    let facts = Facts.facts(item.entity.domain)
                    let unconfirmed = KhalaConfirmGate.call(intent, on: control, entity: item.entity,
                                                            attributes: item.attributes, facts: facts)
                    if let unconfirmed {
                        #expect(!Self.isDangerous(unconfirmed, item),
                                "\(intent) on \(control.title) \(item.entity.state) \(item.attributes) → \(unconfirmed.name)")
                    }
                    // Whatever is dangerous once confirmed is exactly what the control's own dialog asks about, so
                    // the screen never silently drops a tap the gate would refuse.
                    if let confirmed = KhalaConfirmGate.call(.confirmed(intent), on: control, entity: item.entity,
                                                             attributes: item.attributes, facts: facts),
                       Self.isDangerous(confirmed, item) {
                        dangerousSeen += 1
                        #expect(unconfirmed == nil, "\(intent) on \(control.title)")
                        if control.title != "Bare" {
                            #expect(control.confirmation(for: intent) != nil, "\(intent) on \(control.title)")
                        }
                    }
                }
            }
        }
        // The table really can unlock and open once confirmed (the test above isn't vacuous).
        #expect(dangerousSeen > 100)
    }

    @Test func everyTapAndCommandOfAHeroAsksWhereTheGateWould() {
        for item in Self.dangerous {
            for control in Self.controls(item) where control.title != "Bare" {
                var intents = Self.intents
                if let tap = control.tapIntent { intents.append(tap) }
                if case let .commands(commands) = control.kind { intents += commands.map { .command($0) } }
                for intent in intents {
                    let gate = KhalaConfirmGate.confirmation(for: intent, on: control, entity: item.entity,
                                                             attributes: item.attributes)
                    #expect((control.confirmation(for: intent) != nil) == (gate != nil),
                            "\(intent) on \(control.title) \(item.attributes)")
                }
            }
        }
    }

    @Test func theRulesInPlainWords() {
        func ask(_ intent: KhalaIntent, _ domain: String, _ deviceClass: String?, at position: Double? = nil)
            -> KhalaConfirm? {
            KhalaConfirmPolicy.required(intent, domain: domain, deviceClass: deviceClass, position: position)
        }
        // Locks: every unlock route and open ask; locking doesn't.
        #expect(ask(.unlock, "lock", nil) == .unlock)
        #expect(ask(.setOn(true), "lock", nil) == .unlock) // upstream's "on" for a lock is unlock
        #expect(ask(.toggle, "lock", nil) == .unlock)
        #expect(ask(.open, "lock", nil) == .open(deviceClass: nil))
        #expect(ask(.command(.open), "lock", nil) == .open(deviceClass: nil))
        #expect(ask(.lock, "lock", nil) == nil)
        #expect(ask(.setOn(false), "lock", nil) == nil)
        // Garage, gate, door and unclassed covers ask before opening by any route; closing never asks.
        for deviceClass in ["garage", "gate", "door", nil] as [String?] {
            #expect(ask(.command(.open), "cover", deviceClass) == .open(deviceClass: deviceClass))
            #expect(ask(.setOn(true), "cover", deviceClass) == .open(deviceClass: deviceClass))
            #expect(ask(.set(.position, 60), "cover", deviceClass, at: 40) == .open(deviceClass: deviceClass))
            #expect(ask(.set(.position, 60), "cover", deviceClass) == .open(deviceClass: deviceClass))
            #expect(ask(.set(.position, 20), "cover", deviceClass, at: 40) == nil)
            #expect(ask(.command(.close), "cover", deviceClass) == nil)
            #expect(ask(.command(.stop), "cover", deviceClass) == nil)
        }
        // Window coverings don't ask on their own.
        for deviceClass in KhalaConfirmPolicy.quietCoverClasses {
            #expect(ask(.command(.open), "cover", deviceClass) == nil)
        }
        // Other domains never ask.
        #expect(ask(.setOn(true), "switch", "garage") == nil)
    }

    @Test func theCarStillAsksExactlyWhere41Did() {
        // The car's covers are doors (they ask because their tiles declare it, as in 41.1) and its locks ask to
        // unlock; closing and locking go at once — so with the gate in front nothing about the car changes.
        let car = KhalaCarLayout(name: "Rover", members: KhalaScreenFixtures.car,
                                 attributes: KhalaScreenFixtures.carAttributes)
        let byId = Dictionary(KhalaScreenFixtures.car.map { ($0.entityId, $0) }, uniquingKeysWith: { first, _ in first })
        for control in car.overview + car.climateControls + car.chargingControls + car.moreControls {
            guard let entity = byId[control.entityId] else { continue }
            let attributes = KhalaScreenFixtures.carAttributes[control.entityId] ?? [:]
            let model = KhalaControlModel(control, entity: entity, attributes: attributes)
            guard let tap = model.tapIntent else { continue }
            let gate = KhalaConfirmGate.confirmation(for: tap, on: model, entity: entity, attributes: attributes)
            #expect((gate != nil) == control.needsConfirmation, "\(control.entityId)")
            let sent = KhalaConfirmGate.call(control.needsConfirmation ? .confirmed(tap) : tap, on: model,
                                             entity: entity, attributes: attributes,
                                             facts: Facts.facts(entity.domain))
            #expect(sent.map(KhalaGolden.call) == control.call.map { KhalaGolden.call($0.call) }, "\(control.entityId)")
        }
    }

    @Test func aConfirmedIntentHandedStraightToTheTableIsRefused() {
        #expect(KhalaServiceTable.call(.confirmed(.unlock), entityId: "lock.front", state: "locked",
                                       facts: Facts.facts("lock")) == nil)
        // And the gate never lends a control's confirmation to another entity.
        let lock = KhalaLockPanel(entity: Self.entity("lock.front", "locked", [:]), attributes: [:]).controls[0]
        #expect(KhalaConfirmGate.call(.confirmed(.unlock), on: lock, entity: Self.entity("lock.back", "locked", [:]),
                                      attributes: [:], facts: Facts.facts("lock")) == nil)
        #expect(KhalaIntent.confirmed(.confirmed(.unlock)).unconfirmed == .unlock)
    }

    // MARK: - Source scan

    /// Khala's source root: `linux-check.sh` exports it; in Xcode it is four levels above this file.
    private static var sourceRoot: URL {
        if let root = ProcessInfo.processInfo.environment["KHALA_SOURCE_ROOT"] {
            return URL(fileURLWithPath: root)
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func sources() -> [(name: String, text: String)] {
        let khala = sourceRoot.appendingPathComponent("Sources/App/Frontend/Khala")
        return ["Model", "UI"].flatMap { folder -> [(String, String)] in
            let directory = khala.appendingPathComponent(folder)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return names.filter { $0.hasSuffix(".swift") }.compactMap { name in
                (try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)).map {
                    ("\(folder)/\(name)", $0)
                }
            }
        }
    }

    @Test func onlyTheGateReachesTheTableAndOnlyTheDialogConfirms() {
        let files = Self.sources()
        try? #require(files.count > 100, "Khala sources not found under \(Self.sourceRoot.path)")
        guard files.count > 100 else { return }
        let tableCallers = files.filter { $0.text.contains("KhalaServiceTable.call(") }.map(\.name)
        #expect(tableCallers == ["Model/KhalaConfirmGate.swift"])
        // `.confirmed(` built anywhere but the dialog (a pattern `case let .confirmed(` only reads one).
        let makers = files.filter { file in
            file.text.components(separatedBy: "\n").contains { line in
                line.contains(".confirmed(") && !line.contains("case let .confirmed(")
                    && !line.trimmingCharacters(in: .whitespaces).hasPrefix("///")
            }
        }.map(\.name)
        #expect(Set(makers) == ["UI/KhalaConfirmationModifier.swift", "UI/KhalaUpstreamBridge.swift"])
    }
}
