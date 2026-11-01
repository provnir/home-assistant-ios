import Foundation
@testable import HomeAssistant
import Testing

/// HA labels as overrides (decision 2): parsed as data, ids or names, unknown kinds ignored.
struct KhalaLabelOverrideTests {
    @Test func labelIdsAndNamesBothRead() {
        #expect(KhalaLabelOverride.overrides(labels: ["khala_hide"]) == [.hide])
        #expect(KhalaLabelOverride.overrides(labels: ["khala:hide"]) == [.hide])
        #expect(KhalaLabelOverride.overrides(labels: ["khala_kind_light"]) == [.kind(.light)])
        #expect(KhalaLabelOverride.overrides(labels: ["Khala:Kind:Water_Heater"]) == [.kind(.waterHeater)])
        #expect(KhalaLabelOverride.overrides(labels: ["khala_kind_light_group"]) == [.kind(.lightGroup)])
    }

    @Test func otherLabelsAndUnknownKindsAreIgnored() {
        let ignored = ["kitchen", "khala", "khala_kind_", "khala_kind_spaceship"]
        #expect(KhalaLabelOverride.overrides(labels: ignored).isEmpty)
        let mixed = ["outdoor", "khala_hide", "khala_kind_fan"]
        #expect(KhalaLabelOverride.overrides(labels: mixed) == [.hide, .kind(.fan)])
    }
}
