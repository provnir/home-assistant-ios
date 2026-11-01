import Foundation
@testable import HomeAssistant
import Shared
import Testing

/// Slice 2: the car's and generic screen's 41.1 tiles as one grid's models, and the intents their taps make.
struct KhalaControlGridModelTests {
    private typealias Screens = KhalaScreenFixtures

    /// What upstream `Domain` says for the domains the fixtures use (the bridge reads the real thing on iOS).
    static func facts(_ domain: String, state: String = "") -> KhalaUpstreamFacts {
        switch domain {
        case "cover": return KhalaUpstreamFacts(on: .openCover, off: .closeCover, serviceDomain: domain, mainAction: nil)
        case "lock": return KhalaUpstreamFacts(on: .unlock, off: .lock, serviceDomain: domain, mainAction: nil)
        case "button": return KhalaUpstreamFacts(on: .press, off: .press, serviceDomain: domain, mainAction: .press)
        case "group":
            return KhalaUpstreamFacts(on: .turnOn, off: .turnOff, serviceDomain: "homeassistant", mainAction: nil)
        case "select", "number": return KhalaUpstreamFacts(on: nil, off: nil, serviceDomain: domain, mainAction: nil)
        default: return KhalaUpstreamFacts(on: .turnOn, off: .turnOff, serviceDomain: domain, mainAction: nil)
        }
    }

    private static func models(_ controls: [KhalaControl]) -> [KhalaControlModel] {
        let byId = Dictionary(Screens.car.map { ($0.entityId, $0) }, uniquingKeysWith: { first, _ in first })
        return controls.map { control in
            KhalaControlModel(control, entity: byId[control.entityId]!,
                              attributes: Screens.carAttributes[control.entityId] ?? [:])
        }
    }

    private static var layout: KhalaCarLayout {
        KhalaCarLayout(name: "Rover", members: Screens.car, attributes: Screens.carAttributes)
    }

    @Test func carTilesKeepTheirLookAndOrder() {
        let car = Self.layout
        let overview = Self.models(car.overview)
        #expect(overview.map(\.entityId) == car.overview.map(\.entityId))
        #expect(overview.map(\.title) == car.overview.map(\.title))
        #expect(overview.map(\.isActive) == car.overview.map(\.isActive))
        #expect(overview.map(\.stateText) == car.overview.map(\.stateText))
        #expect(overview.map(\.symbol) == car.overview.map { .sf($0.glyph.symbolName) })
        // Enabled exactly where 41.1 had a call (or options).
        for (model, control) in zip(Self.models(car.overview + car.climateControls + car.chargingControls),
                                    car.overview + car.climateControls + car.chargingControls) {
            #expect(model.isEnabled == (control.call != nil || !control.options.isEmpty), "\(control.entityId)")
        }
    }

    /// Every tap makes exactly the call 41.1's tile made, and asks first exactly where it asked.
    @Test func tapsMakeTheSameCallsAs41() {
        let car = Self.layout
        let controls = car.overview + car.climateControls + car.chargingControls + car.moreControls
        let states = Dictionary(Screens.car.map { ($0.entityId, $0.state) }, uniquingKeysWith: { first, _ in first })
        for (model, control) in zip(Self.models(controls), controls) where control.call != nil {
            let intent = try? #require(model.tapIntent)
            guard let intent else { continue }
            let call = KhalaServiceTable.call(intent, entityId: model.entityId, state: states[model.entityId] ?? "",
                                              facts: Self.facts(model.domain))
            #expect(call.map(KhalaGolden.call) == control.call.map { KhalaGolden.call($0.call) }, "\(control.entityId)")
            #expect((model.confirmation(for: intent) != nil) == control.needsConfirmation, "\(control.entityId)")
        }
    }

    @Test func frunkOpensButNeverCloses() {
        let frunk = KhalaControl.make(Screens.car.first { $0.entityId == "cover.rover_frunk" }!,
                                      attributes: ["supported_features": 1])!
        let entity = Screens.car.first { $0.entityId == "cover.rover_frunk" }!
        let model = KhalaControlModel(frunk, entity: entity, attributes: ["supported_features": 1])
        #expect(model.tapIntent == .setOn(true))
        #expect(model.confirmation(for: .setOn(true)) == .open(deviceClass: "door"))
        // Shown open (pending), the tile can't close it.
        let shown = model.showing(KhalaPending(entityId: entity.entityId, value: .on(true), echo: .state(["open"]),
                                               startedAt: Date()))
        #expect(shown.isActive)
        #expect(!shown.isEnabled)
        #expect(shown.tapIntent == nil)
    }

    @Test func unavailableCoverIsIdleAndDisabled() {
        let entity = Screens.entity("cover.gate", "unavailable", ["supported_features": 3])
        let model = KhalaControlModel(KhalaControl.make(entity, attributes: ["supported_features": 3])!, entity: entity,
                                      attributes: ["supported_features": 3])
        #expect(!model.isActive)
        #expect(!model.isEnabled)
        #expect(model.tapIntent == nil)
    }

    @Test func lockUnknownIsDisabledAndUnlockAsks() {
        let entity = Screens.entity("lock.door", "unknown", device: "d", deviceName: "D")
        let control = KhalaControl.make(entity, attributes: [:])!
        let model = KhalaControlModel(control, entity: entity, attributes: [:])
        #expect(!model.isEnabled)
        #expect(model.stateText == KhalaControl.unknownStateText)
        let locked = Screens.entity("lock.door", "locked")
        let lockModel = KhalaControlModel(KhalaControl.make(locked, attributes: [:])!, entity: locked,
                                          attributes: ["supported_features": 1])
        #expect(lockModel.tapIntent == .unlock)
        #expect(lockModel.confirmation(for: .unlock) == .unlock)
        #expect(lockModel.confirmation(for: .lock) == nil)
        #expect(lockModel.kind == .lock(isLocked: true, canOpen: true))
        let shown = lockModel.showing(KhalaPending(entityId: "lock.door", value: .locked(false),
                                                   echo: .state(["unlocked"]), startedAt: Date()))
        #expect(shown.kind == .lock(isLocked: false, canOpen: true))
        #expect(shown.symbol == .sf("lock.open.fill"))
        #expect(shown.stateText == "Unlocked")
        #expect(shown.tapIntent == .lock)
    }

    @Test func overlayShowsPendingValues() {
        let setting = KhalaNumberSetting(entityId: "number.limit", title: "Limit", value: 80, minimum: 50,
                                         maximum: 100, step: 1, unit: "%")
        let stepper = KhalaControlModel(entityId: "number.limit", title: "Limit", symbol: .sf("bolt"),
                                        kind: .stepper(setting), confirm: nil)
        let pending = KhalaPending(entityId: "number.limit", value: .number(85), echo: .stateNumber(85, tolerance: 0),
                                   startedAt: Date())
        #expect(stepper.showing(pending).kind == .stepper(setting.with(value: 85)))
        #expect(stepper.showing(nil) == stepper)
        #expect(stepper.valueIntent(85) == .setNumber(85))
        let target = KhalaControlModel(entityId: "climate.c", title: "Target", symbol: .sf("thermometer.medium"),
                                       kind: .stepper(setting), confirm: nil)
        #expect(target.valueIntent(21.5) == .setTemperature(21.5))
    }

    @Test func mediaSheetIsOneGridOfDistinctControls() {
        let media = KhalaMediaLayout(entity: Screens.receiver, attributes: Screens.receiverAttributes, name: "Den")
        let controls = media.controls
        #expect(controls.map(\.slot) == ["power", "slider", "source", "soundMode"])
        #expect(Set(controls.map(\.id)).count == controls.count)
        #expect(controls[1].kind == .slider(.volume, value: 0.455))
        #expect(controls[2].kind == .choice(current: "Music", options: ["Bluetooth", "Music", "Console"],
                                            field: .source))
        // Off: no volume, sound mode greyed, no source highlighted.
        let off = KhalaMediaLayout(
            entity: Screens.entity("media_player.den_receiver", "off", ["device_class": "receiver"]),
            attributes: Screens.receiverAttributes
        )
        #expect(off.controls.map(\.slot) == ["power", "source", "soundMode"])
        #expect(off.controls.last?.isEnabled == false)
        #expect(off.controls[1].kind == .choice(current: nil, options: ["Bluetooth", "Music", "Console"],
                                                field: .source))
    }

    @Test func genericPowerRow() {
        let plug = Screens.entity("switch.plug", "on")
        let model = KhalaControlModel.power(plug, title: "Power", symbolName: "powerplug")
        #expect(model.tapIntent == .setOn(false))
        #expect(model.isEnabled)
        let gone = KhalaControlModel.power(Screens.entity("switch.plug", "unavailable"), title: "Power",
                                           symbolName: "powerplug")
        #expect(!gone.isEnabled)
        #expect(gone.tapIntent == nil)
    }
}
