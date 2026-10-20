import Foundation

/// One Home Assistant action (service call) a Khala screen wants to make, decided by the Foundation-only model so
/// the rules ("which service turns a Switcher on for 45 minutes?") are testable. `KhalaScreenActions` sends it over
/// the app's websocket as a `call_service` message.
struct KhalaServiceCall {
    let domain: String
    let service: String
    /// `service_data`, `entity_id` included.
    let data: [String: Any]

    init(_ domain: String, _ service: String, entityId: String, data: [String: Any] = [:]) {
        self.domain = domain
        self.service = service
        var merged = data
        merged["entity_id"] = entityId
        self.data = merged
    }

    /// "switch.turn_on", for logs and tests.
    var name: String { "\(domain).\(service)" }

    var entityId: String? { data["entity_id"] as? String }

    /// The plain on/off service for an entity's own domain, e.g. `switch.turn_off`.
    static func power(_ entityId: String, on: Bool) -> KhalaServiceCall {
        let domain = entityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? entityId
        return KhalaServiceCall(domain, on ? "turn_on" : "turn_off", entityId: entityId)
    }
}
