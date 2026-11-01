import Foundation
@testable import HomeAssistant
import Testing

/// `KhalaAccent`: the colour families, whose raw values are persisted in the role assignments.
struct KhalaAccentTests {
    @Test func rawValuesAreStableBecauseTheyArePersisted() {
        #expect(KhalaAccent.allCases.map(\.rawValue) == ["security", "car", "heat", "media", "sun", "neutral"])
        for category in KhalaAccent.allCases {
            #expect(KhalaAccent(rawValue: category.rawValue) == category)
        }
    }

    @Test func codableRoundTripAndUnknownValuesAreRejected() throws {
        let data = try JSONEncoder().encode(KhalaAccent.allCases)
        #expect(String(decoding: data, as: UTF8.self) == #"["security","car","heat","media","sun","neutral"]"#)
        #expect(try JSONDecoder().decode([KhalaAccent].self, from: data) == KhalaAccent.allCases)
        #expect((try? JSONDecoder().decode([KhalaAccent].self, from: Data(#"["bogus"]"#.utf8))) == nil)
    }

    @Test func sunIsNeverAnAssignableRoleNorAChip() {
        #expect(!KhalaAccent.assignableRoles.contains(.sun))
        #expect(!KhalaAccent.chipPriority.contains(.sun))
        #expect(Set(KhalaAccent.assignableRoles) == Set(KhalaAccent.chipPriority))
    }
}
