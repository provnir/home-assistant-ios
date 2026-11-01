import Foundation
@testable import HomeAssistant
import Shared
import Testing

/// The intent → service table (DESIGN §2), with upstream `Service` names.
struct KhalaServiceTableTests {
    private func call(_ intent: KhalaIntent, _ entityId: String, state: String = "off") -> String? {
        let domain = String(entityId.split(separator: ".").first!)
        return KhalaServiceTable.call(intent, entityId: entityId, state: state,
                                      facts: KhalaControlGridModelTests.facts(domain)).map(KhalaGolden.call)
    }

    @Test func onOffAndToggle() {
        #expect(call(.setOn(true), "switch.a") == "switch.turn_on(switch.a)")
        #expect(call(.setOn(false), "light.a") == "light.turn_off(light.a)")
        #expect(call(.setOn(true), "cover.a") == "cover.open_cover(cover.a)")
        #expect(call(.setOn(true), "group.a") == "homeassistant.turn_on(group.a)")
        #expect(call(.toggle, "switch.a", state: "off") == "switch.turn_on(switch.a)")
        #expect(call(.toggle, "switch.a", state: "on") == "switch.turn_off(switch.a)")
        #expect(call(.toggle, "cover.a", state: "open") == "cover.close_cover(cover.a)")
        #expect(call(.setOn(true), "select.a") == nil)
        #expect(call(.press, "button.a") == "button.press(button.a)")
        #expect(call(.press, "switch.a") == nil)
    }

    @Test func locksAndOpening() {
        #expect(call(.lock, "lock.a") == "lock.lock(lock.a)")
        #expect(call(.unlock, "lock.a") == "lock.unlock(lock.a)")
        #expect(call(.open, "lock.a") == "lock.open(lock.a)")
        #expect(call(.open, "cover.a") == "cover.open_cover(cover.a)")
        #expect(call(.unlock, "switch.a") == nil)
    }

    @Test func valuesAndChoices() {
        #expect(call(.set(.volume, 0.4567), "media_player.a") == "media_player.volume_set(media_player.a){volume_level=0.46}")
        #expect(call(.set(.volume, 1.4), "media_player.a") == "media_player.volume_set(media_player.a){volume_level=1.0}")
        #expect(call(.set(.brightness, 70.4), "light.a") == "light.turn_on(light.a){brightness_pct=70}")
        #expect(call(.set(.position, 33), "cover.a") == "cover.set_cover_position(cover.a){position=33}")
        #expect(call(.set(.percentage(step: 25), 60), "fan.a") == "fan.set_percentage(fan.a){percentage=50}")
        #expect(call(.setTemperature(21.5), "climate.a") == "climate.set_temperature(climate.a){temperature=21.5}")
        #expect(call(.setNumber(80), "number.a") == "number.set_value(number.a){value=80.0}")
        #expect(call(.choose(.option, "low"), "select.a") == "select.select_option(select.a){option=low}")
        #expect(call(.choose(.source, "Music"), "media_player.a") == "media_player.select_source(media_player.a){source=Music}")
        #expect(call(.choose(.soundMode, "MOVIE"), "media_player.a")
            == "media_player.select_sound_mode(media_player.a){sound_mode=MOVIE}")
        #expect(call(.choose(.hvacMode, "cool"), "climate.a") == "climate.set_hvac_mode(climate.a){hvac_mode=cool}")
        #expect(call(.choose(.presetMode, "eco"), "fan.a") == "fan.set_preset_mode(fan.a){preset_mode=eco}")
        #expect(call(.set(.volume, 0.5), "light.a") == nil)
    }

    @Test func commands() {
        #expect(call(.command(.returnHome), "vacuum.a") == "vacuum.return_to_base(vacuum.a)")
        #expect(call(.command(.locate), "vacuum.a") == "vacuum.locate(vacuum.a)")
        #expect(call(.command(.stop), "cover.a") == "cover.stop_cover(cover.a)")
        #expect(call(.command(.locate), "cover.a") == nil)
        #expect(call(.timedOn(minutes: 45), "switch.a") == nil)
    }

    /// The media sheet's calls are 41.1's (`KhalaMediaLayout`'s own builders).
    @Test func mediaMatches41() {
        let media = KhalaMediaLayout(entity: KhalaScreenFixtures.receiver,
                                     attributes: KhalaScreenFixtures.receiverAttributes)
        let id = media.entityId
        #expect(call(.setOn(false), id) == KhalaGolden.call(media.power(on: false)))
        #expect(call(.set(.volume, 0.333), id) == KhalaGolden.call(media.setVolume(0.333)))
        #expect(call(.choose(.source, "Console"), id) == KhalaGolden.call(media.selectSource("Console")))
        #expect(call(.choose(.soundMode, "MOVIE"), id) == KhalaGolden.call(media.selectSoundMode("MOVIE")))
    }
}
