import Foundation
@testable import HomeAssistant
import Testing

/// Two cars in one home: the Now card shows the one the user chose, not whichever detection lists first.
struct KhalaNowChoiceTests {
    private static func car(_ id: String, _ name: String) -> KhalaDevice {
        KhalaDevice(id: id, name: name, kind: .car, primaryEntityId: "sensor.\(id)", stateText: "50%",
                    memberEntityIds: [], isPinned: false)
    }

    private static let devices = [
        car("dev-a", "Model Y"),
        car("dev-b", "Model 3"),
        KhalaDevice(id: "dev-h", name: "Boiler", kind: .waterHeater, primaryEntityId: "switch.h", stateText: "Off",
                    memberEntityIds: [], isPinned: false),
    ]

    @Test func firstCarWithoutAChoice() {
        #expect(KhalaDeviceCatalog.nowChips(from: Self.devices).map(\.id).prefix(2) == ["dev-a", "dev-h"])
    }

    @Test func chosenCarReplacesTheFirst() {
        let chips = KhalaDeviceCatalog.nowChips(from: Self.devices, choices: [.car: "dev-b"])
        #expect(chips.map(\.id) == ["dev-b", "dev-h", "dev-a"])
    }

    @Test func aChoiceWhoseDeviceIsGoneFallsBack() {
        let chips = KhalaDeviceCatalog.nowChips(from: Self.devices, choices: [.car: "dev-gone"])
        #expect(chips.first?.id == "dev-a")
    }

    @Test func aChoiceOnlyCountsForItsOwnCategory() {
        let chips = KhalaDeviceCatalog.nowChips(from: Self.devices, choices: [.heat: "dev-b"])
        #expect(chips.map(\.id) == ["dev-a", "dev-h", "dev-b"])
    }

    @Test func alternativesAreTheCategorysUnpinnedDevices() {
        let pinnedCar = KhalaDevice(id: "pin:x", name: "Pinned", kind: .car, primaryEntityId: "sensor.x",
                                    stateText: "", memberEntityIds: [], isPinned: true)
        let alternatives = KhalaDeviceCatalog.nowAlternatives(for: .car, in: Self.devices + [pinnedCar])
        #expect(alternatives.map(\.id) == ["dev-a", "dev-b"])
    }

    @Test func choicesRoundTripPerServer() throws {
        let suite = "khala-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = KhalaNowChoiceStore(defaults: defaults)
        store.save([.car: "dev-b"], serverId: "a")
        #expect(store.load(serverId: "a") == [.car: "dev-b"])
        #expect(store.load(serverId: "b").isEmpty)
        store.save([:], serverId: "a")
        #expect(store.load(serverId: "a").isEmpty)
    }
}
