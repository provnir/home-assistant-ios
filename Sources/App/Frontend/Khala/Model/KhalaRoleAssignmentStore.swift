import Foundation

/// Persists `KhalaRoleAssignment`s per server as JSON in the app's shared `UserDefaults` suite, next to the
/// app's other preferences (`prefs` in `AppDelegate.swift`). Injected so tests use a throwaway suite.
struct KhalaRoleAssignmentStore {
    let defaults: UserDefaults

    func load(serverId: String) -> [KhalaRoleAssignment] {
        guard let data = defaults.data(forKey: Self.key(serverId: serverId)),
              let assignments = try? JSONDecoder().decode([KhalaRoleAssignment].self, from: data) else {
            return []
        }
        return assignments
    }

    func save(_ assignments: [KhalaRoleAssignment], serverId: String) {
        if assignments.isEmpty {
            defaults.removeObject(forKey: Self.key(serverId: serverId))
        } else if let data = try? JSONEncoder().encode(assignments) {
            defaults.set(data, forKey: Self.key(serverId: serverId))
        }
    }

    static func key(serverId: String) -> String {
        "khala.roleAssignments.\(serverId)"
    }
}
