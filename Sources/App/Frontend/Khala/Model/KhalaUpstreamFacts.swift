import Foundation
import Shared

/// What Home Assistant's own domain model (upstream `Domain`, iOS-only: it imports UIKit) says about one entity,
/// read by `KhalaUpstreamBridge` and handed to the Linux-tested `KhalaServiceTable`.
struct KhalaUpstreamFacts: Equatable {
    /// `Domain.toggleServices`: the service that turns it on and the one that turns it off.
    var on: Service?
    var off: Service?
    /// `Domain.serviceDomain`: `homeassistant` for groups, else the entity's domain.
    var serviceDomain: String
    /// `Domain.mainAction(state:)`: press a button, activate a scene, run a script.
    var mainAction: Service?
}
