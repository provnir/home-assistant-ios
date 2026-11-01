import Foundation
@testable import HomeAssistant
import Testing

/// The car screen from the hints file against the word rules of 41.1, on every vehicle entity `tesla_fleet` makes:
/// recorded on khala a23d67de0 BEFORE the hints replaced the words, and unchanged since.
struct KhalaCarHintTests {
    private typealias Tesla = KhalaTeslaFleetFixture

    @Test func everyTeslaFleetEntityLandsWhereTheWordRulesPutIt() {
        let car = KhalaCarLayout(name: "Vega", members: Tesla.vehicle, attributes: Tesla.attributes)
        #expect(KhalaGolden.matches("car-tesla-fleet", KhalaGolden.car(car), """
        name: Vega
        battery: 64.0 from sensor.vega_battery_level
        range: ≈ 288 km
        charging: Charging isCharging=true
        chargeLimit: number.vega_charge_limit Charge limit 80.0 [50.0...100.0 by 1.0] %
        chargeCurrent: number.vega_charge_current Charge current 16.0 [0.0...32.0 by 1.0] A
        tracker: device_tracker.vega_location place=At home
        wake: button.vega_wake connectivity=binary_sensor.vega_status awake=false
        media: media_player.vega_media_player
        inside: 21.5 outside: 18.0
        chargerPower: 7 kW timeToFull: 1792501800.0
        climate: climate.vega_cabin_overheat_protection on=false current=21.5 onMode=cool target=climate.vega_cabin_overheat_protection Target 40.0 [30.0...40.0 by 0.5] °
        wakePlan: pressAndWait button.vega_wake binary_sensor.vega_status
        [overview]
        lock.vega_lock | Lock | Locked | lock | active | lock.unlock(lock.vega_lock) | - | confirm
        switch.vega_sentry_mode | Sentry mode | On | shield | active | switch.turn_off(switch.vega_sentry_mode) | - | -
        cover.vega_charge_port_door | Charge port door | Open | chargePort | active | cover.close_cover(cover.vega_charge_port_door) | - | -
        cover.vega_frunk | Frunk | Closed | frunk | idle | cover.open_cover(cover.vega_frunk) | - | confirm
        cover.vega_trunk | Trunk | Closed | trunk | idle | cover.open_cover(cover.vega_trunk) | - | confirm
        cover.vega_sunroof | Sunroof | Closed | window | idle | cover.open_cover(cover.vega_sunroof) | - | confirm
        cover.vega_windows | Windows | Closed | window | idle | cover.open_cover(cover.vega_windows) | - | confirm
        button.vega_flash_lights | Flash lights |  | lights | idle | button.press(button.vega_flash_lights) | - | -
        button.vega_honk_horn | Honk horn |  | horn | idle | button.press(button.vega_honk_horn) | - | -
        switch.vega_valet_mode | Valet mode | Off | power | idle | switch.turn_on(switch.vega_valet_mode) | - | -
        [more]
        button.vega_homelink | Homelink |  | button | idle | button.press(button.vega_homelink) | - | -
        button.vega_keyless_driving | Keyless driving |  | button | idle | button.press(button.vega_keyless_driving) | - | -
        button.vega_play_fart | Play fart |  | button | idle | button.press(button.vega_play_fart) | - | -
        [climate]
        switch.vega_auto_seat_climate_left | Auto seat climate left | Off | seat | idle | switch.turn_on(switch.vega_auto_seat_climate_left) | - | -
        switch.vega_auto_seat_climate_right | Auto seat climate right | On | seat | active | switch.turn_off(switch.vega_auto_seat_climate_right) | - | -
        select.vega_seat_heater_front_left | Seat heater front left | Off | seat | idle | - | off/low/medium/high | -
        select.vega_seat_heater_front_right | Seat heater front right | Low | seat | active | - | off/low/medium/high | -
        select.vega_seat_heater_rear_center | Seat heater rear center | Off | seat | idle | - | off/low/medium/high | -
        select.vega_seat_heater_rear_left | Seat heater rear left | Off | seat | idle | - | off/low/medium/high | -
        select.vega_seat_heater_rear_right | Seat heater rear right | Off | seat | idle | - | off/low/medium/high | -
        select.vega_seat_heater_third_row_left | Seat heater third row left | Unavailable | seat | idle | - | - | -
        select.vega_seat_heater_third_row_right | Seat heater third row right | Unavailable | seat | idle | - | - | -
        switch.vega_auto_steering_wheel_heater | Auto steering wheel heater | Off | wheel | idle | switch.turn_on(switch.vega_auto_steering_wheel_heater) | - | -
        select.vega_steering_wheel_heater | Steering wheel heater | Off | wheel | idle | - | off/low/high | -
        switch.vega_defrost | Defrost | Off | defrost | idle | switch.turn_on(switch.vega_defrost) | - | -
        [charging]
        lock.vega_charge_cable_lock | Charge cable lock | Unlocked | unlock | idle | lock.lock(lock.vega_charge_cable_lock) | - | -
        cover.vega_charge_port_door | Charge port door | Open | chargePort | active | cover.close_cover(cover.vega_charge_port_door) | - | -
        switch.vega_charge | Charge | On | power | active | switch.turn_off(switch.vega_charge) | - | -
        """))
    }
}
