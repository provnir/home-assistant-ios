import Foundation

/// What a Home Assistant server offers, as far as its settings pages go: the integrations it has loaded
/// (`get_config` → `components`), whether the user is an administrator, and the identity facts the Settings
/// screen's server card shows. Unknown until the server answers; every rule treats "unknown" as "not loaded"
/// except for core pages, which the frontend always shows.
struct KhalaServerCapabilities: Hashable {
    /// Loaded integrations (`hassio` means the Supervisor is there). Nil until `get_config` answered.
    var components: Set<String>?
    /// Nil until the user is known.
    var isAdmin: Bool?
    /// `get_config` → `version` ("2026.10.2").
    var version: String?
    /// `get_config` → `location_name` (the home's name).
    var locationName: String?

    init(components: Set<String>? = nil, isAdmin: Bool? = nil, version: String? = nil, locationName: String? = nil) {
        self.components = components
        self.isAdmin = isAdmin
        self.version = version
        self.locationName = locationName
    }

    /// Reads `get_config`'s answer into the capabilities (the user's admin flag is kept).
    func merging(config json: Any?) -> KhalaServerCapabilities {
        guard let json = json as? [String: Any] else { return self }
        var copy = self
        if let components = json["components"] as? [Any] {
            copy.components = Set(components.compactMap { $0 as? String })
        }
        copy.version = KhalaValue.string(json["version"]) ?? version
        copy.locationName = KhalaValue.string(json["location_name"]) ?? locationName
        return copy
    }

    /// The Supervisor runs this server (Home Assistant OS / Supervised): apps exist.
    var hasSupervisor: Bool { components?.contains("hassio") == true }

    func hasLoaded(_ component: String) -> Bool {
        components?.contains(component) == true
    }
}
