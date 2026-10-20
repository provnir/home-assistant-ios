import Foundation

/// A `KhalaServiceCall` without its payload's `Any`, so controls stay `Equatable`.
struct KhalaServiceCallPlan: Equatable {
    let domain: String
    let service: String
    let entityId: String

    var call: KhalaServiceCall { KhalaServiceCall(domain, service, entityId: entityId) }
}
