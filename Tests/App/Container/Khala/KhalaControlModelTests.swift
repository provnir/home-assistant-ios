import Foundation
@testable import HomeAssistant
import Testing

/// The shapes slice 2 builds on: controls and intents are plain values.
struct KhalaControlModelTests {
    @Test func controlsAndIntentsCompareByValue() {
        let setting = KhalaNumberSetting(entityId: "climate.x", title: "Target", value: 21, minimum: 16, maximum: 30,
                                         step: 0.5, unit: "°")
        let stepper = KhalaControlModel(entityId: "climate.x", title: "Target", symbol: .sf("thermometer.medium"),
                                        kind: .stepper(setting), confirm: nil)
        #expect(stepper.id == "climate.x#value")
        #expect(stepper == KhalaControlModel(entityId: "climate.x", title: "Target", symbol: .sf("thermometer.medium"),
                                             kind: .stepper(setting), confirm: nil))
        let gate = KhalaControlModel(entityId: "cover.g", title: "Gate", symbol: .mdi("mdi:gate"),
                                     kind: .commands([.open, .stop, .close]), confirm: .open(deviceClass: "gate"))
        #expect(gate != stepper)
        #expect(KhalaIntent.set(.percentage(step: 25), 50) != .set(.percentage(step: 20), 50))
        #expect(KhalaIntent.choose(.hvacMode, "cool") == .choose(.hvacMode, "cool"))
        #expect(KhalaIntent.timedOn(minutes: 45) != .timedOn(minutes: 30))
    }
}
