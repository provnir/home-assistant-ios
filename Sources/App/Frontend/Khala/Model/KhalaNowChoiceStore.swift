import Foundation

/// The Now card's "which one" choices: for a category (`KhalaAccent`) that has more than one device — two cars in one
/// home — the device id the user picked to show, instead of whichever detection lists first. Persisted per server as
/// JSON `{accent raw value: device id}` in the app's shared `UserDefaults` suite, like `KhalaRoleAssignmentStore`.
/// A choice whose device is gone is simply ignored (`KhalaDeviceCatalog.nowChips`), so nothing needs cleaning up.
struct KhalaNowChoiceStore {
    let defaults: UserDefaults

    func load(serverId: String) -> [KhalaAccent: String] {
        guard let data = defaults.data(forKey: Self.key(serverId: serverId)),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return raw.reduce(into: [KhalaAccent: String]()) { result, pair in
            if let accent = KhalaAccent(rawValue: pair.key) { result[accent] = pair.value }
        }
    }

    func save(_ choices: [KhalaAccent: String], serverId: String) {
        if choices.isEmpty {
            defaults.removeObject(forKey: Self.key(serverId: serverId))
            return
        }
        let raw = Dictionary(uniqueKeysWithValues: choices.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Self.key(serverId: serverId))
        }
    }

    static func key(serverId: String) -> String {
        "khala.nowChoices.\(serverId)"
    }
}
