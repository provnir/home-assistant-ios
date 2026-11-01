import Foundation
@testable import HomeAssistant
import Shared
import Testing

/// Slice 3: the light and fan heroes, a group's master and members, the fan's percentage-step snap, the intents
/// their controls make and the template the screen picks. Synthetic fixtures only.
struct KhalaLightFanScreenTests {
    private typealias Kinds = KhalaKindFixtures
    private typealias Facts = KhalaControlGridModelTests

    private static func attributes(_ entity: KhalaEntity) -> [String: Any] {
        Kinds.attributes[entity.entityId] ?? [:]
    }

    private static func call(_ intent: KhalaIntent, _ entity: KhalaEntity) -> String {
        guard let call = KhalaServiceTable.call(intent, entityId: entity.entityId, state: entity.state,
                                                facts: Facts.facts(entity.domain)) else { return "-" }
        return KhalaGolden.call(call)
    }

    // MARK: - Light

    @Test func aTunableWhiteLightShowsPowerBrightnessAndWarmth() {
        let panel = KhalaLightPanel(entity: Kinds.deskLamp, attributes: Self.attributes(Kinds.deskLamp))
        #expect(panel.subtitle == "On · 70% · 2700 K")
        #expect(panel.controls.map(\.title) == ["Power", "Brightness", "Warmth"])
        #expect(panel.controls.map(\.slot) == ["power", "slider", "slider"])
        #expect(panel.controls[0].kind == .toggle(isOn: true))
        #expect(panel.controls[1].kind == .slider(.brightness, value: 70))
        #expect(panel.controls[2].kind == .slider(.colorTemp(minKelvin: 2200, maxKelvin: 6500), value: 2700))
        #expect(panel.controls[2].stateText == "2700 K")
        #expect(panel.members.isEmpty)
        #expect(!panel.isGroup)
    }

    @Test func anOnOffLightIsJustPower() {
        let panel = KhalaLightPanel(entity: Kinds.hallBulb, attributes: Self.attributes(Kinds.hallBulb))
        #expect(panel.subtitle == "Off")
        #expect(panel.controls.map(\.title) == ["Power"])
        #expect(panel.controls[0].symbol == .sf("lightbulb"))
        #expect(panel.controls[0].tapIntent == .setOn(true))
    }

    @Test func aColourLightOffersColour() {
        let shelf = Kinds.loungeMembers[2]
        var attributes = Self.attributes(shelf)
        attributes["hs_color"] = [30.0, 80.0]
        let panel = KhalaLightPanel(entity: shelf, attributes: attributes)
        #expect(panel.controls.map(\.title) == ["Power", "Brightness", "Colour"])
        #expect(panel.controls[2].kind == .color(hue: 30, saturation: 80))
        #expect(panel.controls[2].slot == "color")
        #expect(Self.call(.setColor(hue: 30.04, saturation: 120), shelf) == "light.turn_on(light.lounge_shelf){hs_color=[30.0, 100.0]}")
        // Off, the light reports no colour and no brightness.
        let off = KhalaLightPanel(entity: Kinds.loungeMembers[1], attributes: ["supported_color_modes": ["hs"]])
        #expect(off.controls[1].kind == .slider(.brightness, value: 0))
        #expect(off.controls[2].kind == .color(hue: nil, saturation: nil))
    }

    @Test func aGroupHasAMasterAndItsMembers() {
        let members = Kinds.loungeMembers.map { ($0, Self.attributes($0)) }
        let panel = KhalaLightPanel(entity: Kinds.loungeGroup, attributes: Self.attributes(Kinds.loungeGroup),
                                    members: members)
        #expect(panel.isGroup)
        #expect(panel.subtitle == "2 of 3 on")
        #expect(panel.controls.map(\.title) == ["All lights", "Brightness"])
        #expect(panel.controls[0].symbol == .sf("lightbulb.2.fill"))
        #expect(panel.controls[1].kind == .slider(.brightness, value: 60))
        #expect(panel.members.map(\.entityId) == Kinds.loungeMembers.map(\.entityId))
        #expect(panel.members.map(\.title) == ["Lounge ceiling", "Lounge floor", "Lounge shelf"])
        #expect(panel.members.map(\.stateText) == ["80%", "Off", "40%"])
        #expect(panel.members.map(\.tapIntent) == [.setOn(false), .setOn(true), .setOn(false)])
        // Each member row is its own control: tapping one never shows on the master.
        #expect(Set(panel.members.map(\.id)).count == 3)
        #expect(!panel.members.map(\.id).contains(panel.controls[0].id))
    }

    @Test func lightIntentsBecomeLightCalls() {
        let lamp = Kinds.deskLamp
        let warmth = KhalaSlider.colorTemp(minKelvin: 2200, maxKelvin: 6500)
        #expect(Self.call(.set(.brightness, 42.4), lamp) == "light.turn_on(light.desk_lamp){brightness_pct=42}")
        #expect(Self.call(.set(warmth, 3012), lamp) == "light.turn_on(light.desk_lamp){color_temp_kelvin=3000}")
        #expect(Self.call(.set(warmth, 9000), lamp) == "light.turn_on(light.desk_lamp){color_temp_kelvin=6500}")
        #expect(Self.call(.setOn(false), Kinds.loungeGroup) == "light.turn_off(light.lounge_lights)")
        #expect(Self.call(.setColor(hue: 1, saturation: 1), Kinds.atticFan) == "-")
        #expect(Self.call(.set(warmth, 3000), Kinds.atticFan) == "-")
    }

    @Test func warmthAndColourShowAtOnceAndSettle() {
        let panel = KhalaLightPanel(entity: Kinds.deskLamp, attributes: Self.attributes(Kinds.deskLamp))
        let warmth = panel.controls[2]
        let pending = warmth.pendingValue(for: .set(.colorTemp(minKelvin: 2200, maxKelvin: 6500), 4000))
        #expect(pending?.value == .number(4000))
        // Lights report kelvin through mireds: 3984 K still proves 4000 K landed.
        #expect(pending?.echo.isEchoed(by: Kinds.deskLamp, attributes: ["color_temp_kelvin": 3984]) == true)
        #expect(pending?.echo.isEchoed(by: Kinds.deskLamp, attributes: ["color_temp_kelvin": 2700]) == false)
        let colour = KhalaControlModel(entityId: "light.x", title: "Colour", symbol: .sf("paintpalette.fill"),
                                       kind: .color(hue: nil, saturation: nil), confirm: nil)
        let shown = colour.showing(KhalaPending(entityId: "light.x", value: .color(hue: 200, saturation: 50),
                                                echo: .none, startedAt: KhalaTestFixtures.now))
        #expect(shown.kind == .color(hue: 200, saturation: 50))
    }

    // MARK: - Fan

    @Test func percentageStepSnaps() {
        let fourSpeeds = KhalaSlider.percentage(step: 25)
        #expect([0, 10, 12.4, 12.6, 37, 60, 63, 88, 100, 140].map(fourSpeeds.snapped) == [0, 0, 0, 25, 25, 50, 75, 100, 100, 100])
        let threeSpeeds = KhalaSlider.percentage(step: 100.0 / 3)
        #expect([20, 50, 70, 99].map(threeSpeeds.snapped) == [33, 67, 67, 100])
        #expect(KhalaSlider.percentage(step: 1).snapped(42.6) == 43)
        #expect(fourSpeeds.value(atFraction: 0.6) == 50)
        #expect(fourSpeeds.fraction(75) == 0.75)
        let warmth = KhalaSlider.colorTemp(minKelvin: 2000, maxKelvin: 6500)
        #expect(warmth.snapped(2712) == 2700)
        #expect(warmth.value(atFraction: 0) == 2000)
        #expect(warmth.fraction(6500) == 1)
        #expect(KhalaSlider.colorTemp(minKelvin: 3000, maxKelvin: 3000).fraction(3000) == 0)
    }

    @Test func aFanShowsSpeedOscillationAndPreset() {
        let panel = KhalaFanPanel(entity: Kinds.atticFan, attributes: Self.attributes(Kinds.atticFan))
        #expect(panel.subtitle == "On · 50%")
        // supported_features 11 = SET_SPEED + OSCILLATE + PRESET_MODE: no direction.
        #expect(panel.controls.map(\.title) == ["Power", "Speed", "Oscillate", "Preset"])
        #expect(panel.controls[1].kind == .slider(.percentage(step: 25), value: 50))
        #expect(panel.controls[2].kind == .flag(.oscillate, isOn: false))
        #expect(panel.controls[2].slot == "oscillate")
        #expect(panel.controls[2].tapIntent == .setFlag(.oscillate, true))
        #expect(panel.controls[3].kind == .choice(current: nil, options: ["auto", "sleep"], field: .presetMode))
        #expect(Set(panel.controls.map(\.id)).count == panel.controls.count)
    }

    @Test func aFanWithDirectionAndNoSpeed() {
        let fan = KhalaTestFixtures.entity("fan.loft", "off", ["supported_features": 4, "direction": "reverse"])
        let panel = KhalaFanPanel(entity: fan, attributes: ["supported_features": 4, "direction": "reverse"])
        #expect(panel.subtitle == "Off")
        #expect(panel.controls.map(\.title) == ["Power", "Direction"])
        #expect(panel.controls[1].kind == .choice(current: "reverse", options: ["forward", "reverse"],
                                                  field: .direction))
    }

    @Test func fanIntentsBecomeFanCalls() {
        let fan = Kinds.atticFan
        #expect(Self.call(.set(.percentage(step: 25), 60), fan) == "fan.set_percentage(fan.attic_fan){percentage=50}")
        #expect(Self.call(.set(.percentage(step: 25), 63), fan) == "fan.set_percentage(fan.attic_fan){percentage=75}")
        #expect(Self.call(.setFlag(.oscillate, true), fan) == "fan.oscillate(fan.attic_fan){oscillating=true}")
        #expect(Self.call(.choose(.direction, "forward"), fan) == "fan.set_direction(fan.attic_fan){direction=forward}")
        #expect(Self.call(.choose(.presetMode, "sleep"), fan) == "fan.set_preset_mode(fan.attic_fan){preset_mode=sleep}")
        #expect(Self.call(.setFlag(.oscillate, true), Kinds.deskLamp) == "-")
        #expect(Self.call(.choose(.direction, "forward"), Kinds.deskLamp) == "-")
    }

    @Test func oscillationShowsAtOnceAndSettlesOnItsAttribute() {
        let panel = KhalaFanPanel(entity: Kinds.atticFan, attributes: Self.attributes(Kinds.atticFan))
        let oscillate = panel.controls[2]
        let pending = oscillate.pendingValue(for: .setFlag(.oscillate, true))
        #expect(pending?.value == .on(true))
        #expect(pending?.echo.isEchoed(by: Kinds.atticFan, attributes: ["oscillating": true]) == true)
        #expect(pending?.echo.isEchoed(by: Kinds.atticFan, attributes: ["oscillating": false]) == false)
        let shown = oscillate.showing(KhalaPending(entityId: oscillate.entityId, value: .on(true),
                                                   echo: pending!.echo, startedAt: KhalaTestFixtures.now))
        #expect(shown.kind == .flag(.oscillate, isOn: true))
        #expect(shown.isActive)
        // The power switch of the same fan is untouched by it.
        #expect(panel.controls[0].showing(nil).toggleIsOn == true)
    }

    // MARK: - Template

    private static func layout(_ face: KhalaEntity, members: [KhalaEntity]? = nil) -> KhalaTemplateLayout {
        let all = Kinds.everything
        let byId = Dictionary(all.map { ($0.entityId, $0) }, uniquingKeysWith: { first, _ in first })
        return KhalaTemplateLayout(
            primaryEntityId: face.entityId,
            memberEntityIds: (members ?? [face]).map(\.entityId),
            entities: byId,
            attributes: Kinds.everythingAttributes,
            powerSymbol: "powerplug"
        )
    }

    @Test func theFacePicksTheTemplate() {
        let lamp = Self.layout(Kinds.deskLamp)
        #expect(lamp.spec == .light)
        #expect(lamp.heroStyle == .panel)
        #expect(lamp.subtitle == "On · 70% · 2700 K")
        #expect(lamp.hero.count == 3)

        let group = Self.layout(Kinds.loungeGroup)
        #expect(group.members.map(\.entityId) == Kinds.loungeMembers.map(\.entityId))
        #expect(group.subtitle == "2 of 3 on")

        let fan = Self.layout(Kinds.atticFan)
        #expect(fan.spec == .fan)
        #expect(fan.hero.map(\.title) == ["Power", "Speed", "Oscillate", "Preset"])
    }

    @Test func aSwitchKeepsTheGenericScreen() {
        let plug = Self.layout(Kinds.deskPlug, members: [Kinds.deskPlug, Kinds.deskPlugPower])
        #expect(plug.spec == .generic)
        #expect(plug.heroStyle == .powerCard)
        #expect(plug.hero.map(\.title) == ["Power"])
        #expect(plug.hero.first?.symbol == .sf("powerplug"))
        #expect(plug.subtitle == "On")
        #expect(plug.controls.isEmpty)
        #expect(plug.readings.map(\.entityId) == ["sensor.desk_plug_power"])

        let lock = Self.layout(Kinds.blueDoor, members: [Kinds.blueDoor, Kinds.blueDoorBattery])
        #expect(lock.heroStyle == .tile)
        #expect(lock.hero.first?.kind == .lock(isLocked: true, canOpen: true))

        let sensor = Self.layout(Kinds.deskPlugPower)
        #expect(sensor.heroStyle == .none)
        let missing = KhalaTemplateLayout(primaryEntityId: "light.gone", memberEntityIds: [], entities: [:],
                                          attributes: [:], powerSymbol: "powerplug")
        #expect(missing.primary == nil)
        #expect(missing.heroStyle == .none)
        #expect(missing.subtitle == nil)
    }

    @Test func aFanLightKeepsItsLightAsATile() {
        let fan = KhalaTestFixtures.entity("fan.ceiling", "on", ["supported_features": 1, "percentage": 33],
                                           device: "dev-c", deviceName: "Ceiling")
        let light = KhalaTestFixtures.entity("light.ceiling_light", "off", ["friendly_name": "Ceiling Light"],
                                             device: "dev-c", deviceName: "Ceiling")
        let layout = KhalaTemplateLayout(
            primaryEntityId: fan.entityId,
            memberEntityIds: [fan.entityId, light.entityId],
            entities: [fan.entityId: fan, light.entityId: light],
            attributes: [fan.entityId: ["supported_features": 1, "percentage": 33]],
            powerSymbol: "powerplug"
        )
        #expect(layout.spec == .fan)
        #expect(layout.controls.map(\.entityId) == ["light.ceiling_light"])
        #expect(layout.controls.first?.title == "Light")
        #expect(layout.subtitle == "On · 33%")
    }
}
