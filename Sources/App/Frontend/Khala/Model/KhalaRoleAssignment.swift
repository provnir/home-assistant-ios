import Foundation

/// A user's choice to show one entity as a device with a given role (and optionally a label), e.g. a plain relay
/// switch as "Hot water" with the `heat` role. Types are code (`KhalaCategory`); which entity plays which role is
/// data, stored per server by `KhalaRoleAssignmentStore`.
struct KhalaRoleAssignment: Codable, Equatable, Identifiable {
    var entityId: String
    var role: KhalaCategory
    /// Overrides the entity's friendly name in Khala when set and not blank.
    var label: String?

    var id: String { entityId }

    /// The label to show, or nil when the entity's own name should be used.
    var displayLabel: String? {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else { return nil }
        return label
    }
}
