import Foundation
@testable import HomeAssistant
import Shared
import Testing

/// Slice 4: climate, covers and locks detected through descriptors (and taking their device from a light or a
/// switch on it), their heroes — target stepper, HVAC / fan / preset / swing choices, cover commands, position and
/// tilt, the lock and its open gate — and the calls their intents make. Synthetic fixtures only.
struct KhalaClimateCoverLockTests {
    private typealias Kinds = KhalaKindFixtures
    private typealias Facts = KhalaControlGridModelTests

    private static func entity(
        _ id: String,
        _ state: String,
        _ attributes: [String: Any] = [:],
        device: String? = nil,
        translationKey: String? = nil
    ) -> KhalaEntity {
        KhalaEntity(entityId: id, state: state, lastChanged: KhalaTestFixtures.now, attributes: attributes,
                    deviceId: device, deviceName: device.map { _ in "Gadget" }, translationKey: translationKey)
    }

    private static func attributes(_ entity: KhalaEntity) -> [String: Any] {
        Kinds.attributes[entity.entityId] ?? [:]
    }

    /// The call `intent` makes on `control`, through the gate, as `KhalaGolden.call` text; "-" for none.
    private static func call(_ intent: KhalaIntent, _ control: KhalaControlModel, _ entity: KhalaEntity,
                             _ attributes: [String: Any]) -> String {
        KhalaConfirmGate.call(intent, on: control, entity: entity, attributes: attributes,
                              facts: Facts.facts(entity.domain)).map(KhalaGolden.call) ?? "-"
    }

    // MARK: - Detection

    @Test func climateCoversAndLocksAreDetected() {
        let devices = KhalaDeviceCatalog.build(entities: Kinds.all, assignments: [])
        let byFace = Dictionary(devices.map { ($0.primaryEntityId, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(byFace["climate.study_ac"]?.kind == .climate)
        #expect(byFace["climate.loft_heater"]?.kind == .climate)
        #expect(byFace["cover.shed_door"]?.kind == .cover)
        #expect(byFace["cover.side_gate"]?.kind == .cover)
        #expect(byFace["lock.blue_door"]?.kind == .lock)
        // Existing colour families (decision 3): climate heat, lock security, cover neutral.
        #expect(byFace["climate.study_ac"]?.accent == .heat)
        #expect(byFace["lock.blue_door"]?.accent == .security)
        #expect(byFace["cover.shed_door"]?.accent == .neutral)
        #expect(byFace["lock.blue_door"]?.memberEntityIds == ["lock.blue_door", "sensor.blue_door_battery"])
        // Their templates.
        #expect(KhalaDescriptors.shown(for: Kinds.studyAC).template == .climate)
        #expect(KhalaDescriptors.shown(for: Kinds.shedDoor).template == .cover)
        #expect(KhalaDescriptors.shown(for: Kinds.blueDoor).template == .lock)
    }

    @Test func aGarageOpenerWithALightIsACover() {
        let opener = Self.entity("cover.garage", "closed", ["device_class": "garage", "supported_features": 3],
                                 device: "dev-garage")
        let lamp = Self.entity("light.garage_lamp", "off", device: "dev-garage", translationKey: "light")
        let devices = KhalaDeviceCatalog.build(entities: [lamp, opener], assignments: [])
        #expect(devices.map(\.kind) == [.cover])
        #expect(devices.first?.primaryEntityId == "cover.garage")
        // The light is one of the cover screen's controls, not a device of its own.
        #expect(devices.first?.memberEntityIds == ["light.garage_lamp", "cover.garage"])
        let layout = KhalaTemplateLayout(
            primaryEntityId: "cover.garage", memberEntityIds: ["light.garage_lamp", "cover.garage"],
            entities: ["cover.garage": opener, "light.garage_lamp": lamp],
            attributes: ["cover.garage": ["device_class": "garage", "supported_features": 3]], powerSymbol: "power"
        )
        #expect(layout.spec == .cover)
        #expect(layout.controls.map(\.entityId) == ["light.garage_lamp"])
    }

    @Test func precedenceIsClimateLockCoverFanLightSwitch() {
        func face(_ entities: [KhalaEntity]) -> KhalaKind? {
            KhalaDeviceCatalog.build(entities: entities, assignments: []).first?.kind
        }
        let display = Self.entity("switch.ac_display", "on", device: "d", translationKey: "display")
        let ac = Self.entity("climate.ac", "cool", device: "d")
        let lock = Self.entity("lock.latch", "locked", device: "d")
        let cover = Self.entity("cover.door", "closed", device: "d")
        let fan = Self.entity("fan.vent", "off", device: "d")
        let light = Self.entity("light.lamp", "off", device: "d")
        #expect(face([display, ac]) == .climate)
        #expect(face([cover, lock]) == .lock)
        #expect(face([light, fan, cover]) == .cover)
        #expect(face([light, ac, lock, cover, fan, display]) == .climate)
        // A car keeps its own rule, whatever climate, locks and covers it has.
        #expect(face(KhalaScreenFixtures.car) == .car)
    }

    @Test func detectedClimateRoutesToItsDeviceScreen() {
        let devices = KhalaDeviceCatalog.build(entities: Kinds.all, assignments: [])
        func route(_ id: String) -> String {
            KhalaGolden.route(KhalaRouting.target(forEntityId: id, entities: Kinds.all, devices: devices,
                                                  automationConfigs: [:]))
        }
        #expect(route("climate.study_ac") == "screen device(dev-ac)")
        #expect(route("cover.shed_door") == "screen device(dev-shed)")
        #expect(route("sensor.blue_door_battery") == "screen device(dev-blue)")
    }

    // MARK: - Climate

    @Test func anAirConditionerShowsTargetModeFanPresetAndSwing() {
        let panel = KhalaClimatePanel(entity: Kinds.studyAC, attributes: Self.attributes(Kinds.studyAC))
        #expect(panel.subtitle == "Cool · now 26°")
        #expect(panel.controls.map(\.title) == ["Target", "Mode", "Fan", "Preset", "Swing"])
        #expect(panel.controls.map(\.slot) == ["value", "hvacMode", "fanMode", "presetMode", "swingMode"])
        #expect(Set(panel.controls.map(\.id)).count == panel.controls.count)
        let target = panel.controls[0].numberSetting
        #expect(target?.value == 22.5)
        #expect(target?.minimum == 16)
        #expect(target?.maximum == 30)
        #expect(target?.step == 0.5)
        #expect(target?.text == "22.5°")
        #expect(target?.stepped(1) == 23)
        #expect(target?.with(value: 30).stepped(1) == 30)
        #expect(panel.controls[1].kind == .choice(current: "cool", options: ["off", "cool", "heat", "fan_only"],
                                                  field: .hvacMode))
        #expect(panel.controls[2].kind == .choice(current: "auto", options: ["auto", "low", "high"], field: .fanMode))
        #expect(panel.controls[3].kind == .choice(current: "none", options: ["none", "eco"], field: .presetMode))
        #expect(panel.controls[4].kind == .choice(current: "off", options: ["off", "vertical"], field: .swingMode))
        #expect(panel.controls.allSatisfy { $0.isEnabled })
    }

    @Test func aHeaterOffersOnlyWhatItSupports() {
        let panel = KhalaClimatePanel(entity: Kinds.loftHeater, attributes: Self.attributes(Kinds.loftHeater))
        #expect(panel.subtitle == "Heat · now 18.5°")
        #expect(panel.controls.map(\.title) == ["Target", "Mode"])
        // What it is doing beats its mode; no target feature, no stepper; lists without the feature bit stay hidden.
        var attributes = Self.attributes(Kinds.studyAC)
        attributes["hvac_action"] = "cooling"
        attributes["supported_features"] = 0
        let bare = KhalaClimatePanel(entity: Kinds.studyAC, attributes: attributes)
        #expect(bare.subtitle == "Cooling · now 26°")
        #expect(bare.controls.map(\.title) == ["Mode"])
        // A heat/cool range has no single target to step.
        let range = KhalaClimatePanel(entity: Self.entity("climate.range", "heat_cool", [
            "hvac_modes": ["off", "heat_cool"], "target_temp_low": 20.0, "target_temp_high": 24.0,
            "supported_features": 2,
        ]), attributes: ["hvac_modes": ["off", "heat_cool"], "target_temp_low": 20.0, "target_temp_high": 24.0,
                         "supported_features": 2])
        #expect(range.controls.map(\.title) == ["Mode"])
    }

    @Test func anUnavailableClimateIsDisabled() {
        let gone = Self.entity("climate.study_ac", "unavailable", Self.attributes(Kinds.studyAC))
        let panel = KhalaClimatePanel(entity: gone, attributes: Self.attributes(Kinds.studyAC))
        #expect(panel.subtitle == "Unavailable")
        #expect(panel.controls.allSatisfy { !$0.isEnabled })
        #expect(panel.controls.compactMap(\.tapIntent).isEmpty)
    }

    @Test func climateIntentsBecomeClimateCalls() {
        let ac = Kinds.studyAC
        let attributes = Self.attributes(ac)
        let controls = KhalaClimatePanel(entity: ac, attributes: attributes).controls
        #expect(controls[0].valueIntent(23) == .setTemperature(23))
        #expect(Self.call(.setTemperature(23), controls[0], ac, attributes)
            == "climate.set_temperature(climate.study_ac){temperature=23.0}")
        #expect(Self.call(.choose(.hvacMode, "heat"), controls[1], ac, attributes)
            == "climate.set_hvac_mode(climate.study_ac){hvac_mode=heat}")
        #expect(Self.call(.choose(.fanMode, "low"), controls[2], ac, attributes)
            == "climate.set_fan_mode(climate.study_ac){fan_mode=low}")
        #expect(Self.call(.choose(.presetMode, "eco"), controls[3], ac, attributes)
            == "climate.set_preset_mode(climate.study_ac){preset_mode=eco}")
        #expect(Self.call(.choose(.swingMode, "vertical"), controls[4], ac, attributes)
            == "climate.set_swing_mode(climate.study_ac){swing_mode=vertical}")
        // The optimistic overlay: the stepper shows the new target until HA echoes it.
        let pending = controls[0].pendingValue(for: .setTemperature(23))
        #expect(pending?.value == .number(23))
        #expect(pending?.echo == .attributeNumber("temperature", 23, tolerance: 0.01))
        #expect(controls[0].showing(KhalaPending(entityId: ac.entityId, value: .number(23),
                                                 echo: .attributeNumber("temperature", 23, tolerance: 0.01),
                                                 startedAt: Date())).numberSetting?.text == "23°")
        #expect(controls[1].pendingValue(for: .choose(.hvacMode, "heat"))?.echo == .state(["heat"]))
    }

    // MARK: - Cover

    @Test func aGarageDoorWithPositionShowsCommandsAndPosition() {
        let door = Kinds.shedDoor
        let panel = KhalaCoverPanel(entity: door, attributes: Self.attributes(door))
        #expect(panel.subtitle == "Open · 100%")
        #expect(panel.controls.map(\.slot) == ["commands", "slider"])
        #expect(panel.controls[0].kind == .commands([.open, .stop, .close]))
        #expect(panel.controls[0].title == "Shed door")
        #expect(panel.controls[0].symbol == .sf("door.garage.open"))
        // Fully open: no Open; Stop and Close can go.
        #expect(!panel.controls[0].isEnabled(.open))
        #expect(panel.controls[0].isEnabled(.stop))
        #expect(panel.controls[0].isEnabled(.close))
        #expect(panel.controls[1].kind == .slider(.position, value: 100))
        #expect(panel.controls[1].title == "Position")
    }

    @Test func aGateWithoutPositionIsJustOpenAndClose() {
        let gate = Kinds.sideGate
        let panel = KhalaCoverPanel(entity: gate, attributes: Self.attributes(gate))
        #expect(panel.subtitle == "Closed")
        #expect(panel.controls.map(\.kind) == [.commands([.open, .close])])
        #expect(panel.controls[0].isEnabled(.open))
        #expect(!panel.controls[0].isEnabled(.close))
        let gone = KhalaCoverPanel(entity: Self.entity("cover.side_gate", "unavailable"),
                                   attributes: Self.attributes(gate))
        #expect(!gone.controls[0].isEnabled(.open))
        #expect(!gone.controls[0].isEnabled(.close))
    }

    @Test func tiltIsASliderOrItsOwnCommands() {
        // OPEN 1 | CLOSE 2 | SET_POSITION 4 | STOP 8 | OPEN_TILT 16 | CLOSE_TILT 32 | STOP_TILT 64 | SET_TILT 128.
        let attributes: [String: Any] = ["device_class": "blind", "supported_features": 255, "current_position": 40,
                                         "current_tilt_position": 70]
        let blind = KhalaCoverPanel(entity: Self.entity("cover.blind", "open", attributes), attributes: attributes)
        #expect(blind.controls.map(\.slot) == ["commands", "slider", "tilt"])
        #expect(blind.controls[2].kind == .slider(.tilt, value: 70))
        #expect(Set(blind.controls.map(\.id)).count == 3)
        let slats: [String: Any] = ["device_class": "blind", "supported_features": 3 | 16 | 32 | 64]
        let venetian = KhalaCoverPanel(entity: Self.entity("cover.slats", "closed", slats), attributes: slats)
        #expect(venetian.controls.map(\.slot) == ["commands", "tiltCommands"])
        #expect(venetian.controls[1].kind == .commands([.openTilt, .stopTilt, .closeTilt]))
        #expect(Set(venetian.controls.map(\.id)).count == 2)
    }

    @Test func coverIntentsBecomeCoverCalls() {
        let attributes: [String: Any] = ["device_class": "blind", "supported_features": 255, "current_position": 40]
        let blind = Self.entity("cover.blind", "open", attributes)
        let controls = KhalaCoverPanel(entity: blind, attributes: attributes).controls
        // A blind opens without asking (window coverings let nobody in).
        #expect(Self.call(.command(.open), controls[0], blind, attributes) == "cover.open_cover(cover.blind)")
        #expect(Self.call(.command(.stop), controls[0], blind, attributes) == "cover.stop_cover(cover.blind)")
        #expect(Self.call(.command(.close), controls[0], blind, attributes) == "cover.close_cover(cover.blind)")
        #expect(Self.call(.set(.position, 75), controls[1], blind, attributes)
            == "cover.set_cover_position(cover.blind){position=75}")
        #expect(Self.call(.set(.tilt, 30), controls[2], blind, attributes)
            == "cover.set_cover_tilt_position(cover.blind){tilt_position=30}")
        let tilt = KhalaControlModel(entityId: "cover.blind", title: "Tilt", symbol: .sf("line.3.horizontal"),
                                     kind: .commands([.openTilt, .stopTilt, .closeTilt]), confirm: nil)
        #expect(Self.call(.command(.openTilt), tilt, blind, attributes) == "cover.open_cover_tilt(cover.blind)")
        #expect(Self.call(.command(.stopTilt), tilt, blind, attributes) == "cover.stop_cover_tilt(cover.blind)")
        #expect(Self.call(.command(.closeTilt), tilt, blind, attributes) == "cover.close_cover_tilt(cover.blind)")
        #expect(controls[2].pendingValue(for: .set(.tilt, 30))?.echo
            == .attributeNumber("current_tilt_position", 30, tolerance: 1))
    }

    // MARK: - Lock

    @Test func aLockThatCanOpenShowsLockAndOpen() {
        let door = Kinds.blueDoor
        let panel = KhalaLockPanel(entity: door, attributes: Self.attributes(door))
        #expect(panel.subtitle == "Locked")
        #expect(panel.controls.map(\.slot) == ["lock", "commands"])
        #expect(panel.controls[0].kind == .lock(isLocked: true, canOpen: true))
        #expect(panel.controls[0].stateText == "Locked")
        #expect(panel.controls[0].tapIntent == .unlock)
        #expect(panel.controls[1].kind == .commands([.open]))
        #expect(panel.controls[1].isEnabled(.open))
        // Without the open feature there is no Open.
        let plain = KhalaLockPanel(entity: door, attributes: ["supported_features": 0])
        #expect(plain.controls.map(\.slot) == ["lock"])
        // Unlocked: the tap locks.
        let open = KhalaLockPanel(entity: Self.entity("lock.blue_door", "unlocked"), attributes: Self.attributes(door))
        #expect(open.controls[0].tapIntent == .lock)
        #expect(open.controls[0].symbol == .sf("lock.open.fill"))
    }

    @Test func anUnknownOrUnavailableLockIsDisabled() {
        for state in ["unknown", "unavailable"] {
            let panel = KhalaLockPanel(entity: Self.entity("lock.blue_door", state),
                                       attributes: Self.attributes(Kinds.blueDoor))
            #expect(panel.controls[0].stateText == KhalaControl.unknownStateText, "\(state)")
            #expect(!panel.controls[0].isEnabled, "\(state)")
            #expect(panel.controls[0].tapIntent == nil, "\(state)")
            #expect(!panel.controls[1].isEnabled(.open), "\(state)")
        }
    }

    @Test func lockIntentsBecomeLockCallsOnceConfirmed() {
        let door = Kinds.blueDoor
        let attributes = Self.attributes(door)
        let controls = KhalaLockPanel(entity: door, attributes: attributes).controls
        #expect(Self.call(.lock, controls[0], door, attributes) == "lock.lock(lock.blue_door)")
        #expect(Self.call(.unlock, controls[0], door, attributes) == "-")
        #expect(Self.call(.confirmed(.unlock), controls[0], door, attributes) == "lock.unlock(lock.blue_door)")
        #expect(Self.call(.command(.open), controls[1], door, attributes) == "-")
        #expect(Self.call(.confirmed(.command(.open)), controls[1], door, attributes) == "lock.open(lock.blue_door)")
        // Confirm copy names the lock.
        #expect(controls[0].confirmation(for: .unlock) == .unlock)
        #expect(controls[1].confirmation(for: .command(.open)) == .open(deviceClass: nil))
        #expect(KhalaScreenText.confirmQuestion(.unlock, name: controls[0].title) == "Unlock Blue door?")
        #expect(KhalaScreenText.confirmQuestion(.open(deviceClass: nil), name: controls[1].title) == "Open Blue door?")
        #expect(KhalaScreenText.confirmButton(.unlock) == "Unlock")
    }
}
