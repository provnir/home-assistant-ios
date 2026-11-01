import Foundation
@testable import HomeAssistant
import Testing

/// Slice 3, decision 1: the DEVICES menu grouped by Home Assistant area once it grows.
struct KhalaMenuSectionTests {
    private static func device(_ id: String, area: String?, pinned: Bool = false) -> KhalaDevice {
        KhalaDevice(id: id, name: id.capitalized, kind: .light, primaryEntityId: "light.\(id)", stateText: "On",
                    memberEntityIds: ["light.\(id)"], isPinned: pinned, areaId: area)
    }

    private static let areas = [
        KhalaArea(id: "area_b", name: "Bedroom", sortOrder: 2),
        KhalaArea(id: "area_k", name: "Kitchen", sortOrder: 1),
        KhalaArea(id: "area_s", name: "Study", sortOrder: nil),
        KhalaArea(id: "area_a", name: "Attic", sortOrder: nil),
    ]

    private static func summary(_ sections: [KhalaMenuSection]) -> [String] {
        sections.map { "\($0.title ?? "-"): " + $0.devices.map(\.id).joined(separator: ",") }
    }

    @Test func aShortListStaysFlat() {
        let devices = (1 ... 8).map { Self.device("d\($0)", area: "area_k") }
        let sections = KhalaMenuSection.sections(devices: devices, areas: Self.areas)
        #expect(sections.count == 1)
        #expect(sections.first?.title == nil)
        #expect(sections.first?.devices == devices)
        #expect(KhalaMenuSection.sections(devices: [], areas: Self.areas).isEmpty)
    }

    @Test func aLongListGroupsByAreaWithPinsOnTop() {
        let devices = [
            Self.device("pin", area: "area_s", pinned: true),
            Self.device("lamp", area: "area_b"),
            Self.device("kettle", area: "area_k"),
            Self.device("desk", area: "area_s"),
            Self.device("hatch", area: "area_a"),
            Self.device("stray", area: nil),
            Self.device("ghost", area: "area_gone"),
            Self.device("toaster", area: "area_k"),
            Self.device("bed", area: "area_b"),
        ]
        let sections = KhalaMenuSection.sections(devices: devices, areas: Self.areas)
        // HA's own order first (Kitchen 1, Bedroom 2), then unordered areas by name, then no/unknown area.
        #expect(Self.summary(sections) == [
            "-: pin",
            "Kitchen: kettle,toaster",
            "Bedroom: lamp,bed",
            "Attic: hatch",
            "Study: desk",
            "Other: stray,ghost",
        ])
        #expect(sections.map(\.id) == [KhalaMenuSection.pinnedId, "area_k", "area_b", "area_a", "area_s",
                                       KhalaMenuSection.otherId])
        // Every device appears exactly once.
        #expect(sections.flatMap(\.devices).count == devices.count)
    }

    @Test func aSearchIsAlwaysFlat() {
        let devices = (1 ... 12).map { Self.device("lamp\($0)", area: $0.isMultiple(of: 2) ? "area_k" : "area_b") }
        let sections = KhalaMenuSection.sections(devices: devices, areas: Self.areas, query: " lamp1 ")
        #expect(Self.summary(sections) == ["-: lamp1,lamp10,lamp11,lamp12"])
        #expect(KhalaMenuSection.sections(devices: devices, areas: Self.areas, query: "zzz").isEmpty)
    }
}
