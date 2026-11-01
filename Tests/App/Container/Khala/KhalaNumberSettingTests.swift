import Foundation
@testable import HomeAssistant
import Testing

/// `KhalaNumberSetting`: a `number.*` or climate target adjusted with − / +.
struct KhalaNumberSettingTests {
    private static func entity(_ state: String, unit: String? = nil) -> KhalaEntity {
        var attributes: [String: Any] = ["friendly_name": "Gizmo Target"]
        if let unit { attributes["unit_of_measurement"] = unit }
        return KhalaTestFixtures.entity("number.gizmo_target", state, attributes, device: "d", deviceName: "Gizmo")
    }

    @Test func readsBoundsAndFallsBackToHomeAssistantsDefaults() throws {
        let setting = try #require(KhalaNumberSetting(Self.entity("40", unit: "%"), attributes: [:]))
        #expect(setting.title == "Target")
        #expect(setting.minimum == 0)
        #expect(setting.maximum == 100)
        #expect(setting.step == 1)
        #expect(setting.unit == "%")
        #expect(setting.text == "40%")
        let custom = try #require(KhalaNumberSetting(Self.entity("6"), attributes: ["min": "2", "max": 8, "step": 0.5]))
        #expect(custom.minimum == 2)
        #expect(custom.maximum == 8)
        #expect(custom.step == 0.5)
    }

    @Test func aStateThatIsNoNumberGivesNoSetting() {
        #expect(KhalaNumberSetting(Self.entity("unavailable"), attributes: [:]) == nil)
        #expect(KhalaNumberSetting(Self.entity(""), attributes: [:]) == nil)
    }

    @Test func aZeroOrNegativeStepNeverDividesByZero() throws {
        let zero = try #require(KhalaNumberSetting(Self.entity("5"), attributes: ["step": 0]))
        #expect(zero.step == 0.0001)
        let direct = KhalaNumberSetting(entityId: "number.x", title: "X", value: 1, minimum: 0, maximum: 2, step: -1,
                                        unit: nil)
        #expect(direct.step == 0.0001)
    }

    @Test func steppingSnapsToTheGridAndStaysInBounds() {
        let setting = KhalaNumberSetting(entityId: "climate.x", title: "Target", value: 20.3, minimum: 16, maximum: 22,
                                         step: 0.5, unit: "°")
        #expect(setting.stepped(1) == 21)
        #expect(setting.stepped(-1) == 20)
        #expect(setting.stepped(0) == 20.5)
        #expect(setting.stepped(10) == 22)
        #expect(setting.stepped(-20) == 16)
    }

    @Test func fractionIsClampedAndSafeForAnEmptyRange() {
        func fraction(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
            KhalaNumberSetting(entityId: "n", title: "", value: value, minimum: minimum, maximum: maximum, step: 1,
                               unit: nil).fraction
        }
        #expect(fraction(80, 50, 100) == 0.6)
        #expect(fraction(120, 50, 100) == 1)
        #expect(fraction(10, 50, 100) == 0)
        #expect(fraction(5, 5, 5) == 0)
        #expect(fraction(5, 10, 0) == 0)
    }

    @Test func theCallSetsTheValue() {
        let setting = KhalaNumberSetting(entityId: "number.gizmo_target", title: "Target", value: 1, minimum: 0,
                                         maximum: 10, step: 1, unit: nil)
        let call = setting.call(value: 4)
        #expect(call.name == "number.set_value")
        #expect(call.entityId == "number.gizmo_target")
        #expect(call.data["value"] as? Double == 4)
    }
}
