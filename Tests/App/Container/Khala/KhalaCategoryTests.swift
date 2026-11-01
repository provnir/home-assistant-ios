import Foundation
@testable import HomeAssistant
import Testing

/// `KhalaCategory`: the colour families, whose raw values are persisted in the role assignments.
struct KhalaCategoryTests {
    @Test func rawValuesAreStableBecauseTheyArePersisted() {
        #expect(KhalaCategory.allCases.map(\.rawValue) == ["security", "car", "heat", "media", "sun", "neutral"])
        for category in KhalaCategory.allCases {
            #expect(KhalaCategory(rawValue: category.rawValue) == category)
        }
    }

    @Test func codableRoundTripAndUnknownValuesAreRejected() throws {
        let data = try JSONEncoder().encode(KhalaCategory.allCases)
        #expect(String(decoding: data, as: UTF8.self) == #"["security","car","heat","media","sun","neutral"]"#)
        #expect(try JSONDecoder().decode([KhalaCategory].self, from: data) == KhalaCategory.allCases)
        #expect((try? JSONDecoder().decode([KhalaCategory].self, from: Data(#"["bogus"]"#.utf8))) == nil)
    }

    @Test func sunIsNeverAnAssignableRoleNorAChip() {
        #expect(!KhalaCategory.assignableRoles.contains(.sun))
        #expect(!KhalaCategory.chipPriority.contains(.sun))
        #expect(Set(KhalaCategory.assignableRoles) == Set(KhalaCategory.chipPriority))
    }
}
