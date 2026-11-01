import Foundation
import Shared

/// The one place Khala's controls read Home Assistant's own domain model (upstream `Domain`, `ClimateControlState`),
/// which imports UIKit and `L10n` and so can't run in the Linux-tested `Model/` (DESCRIPTORS-DESIGN.md §2). It only
/// gathers upstream's facts; the intent → service table itself is `KhalaServiceTable`.
enum KhalaUpstreamBridge {
    /// `Domain.toggleServices`, `serviceDomain` and `mainAction(state:)` for `entity`.
    static func facts(for entity: KhalaEntity) -> KhalaUpstreamFacts {
        guard let domain = Domain(rawValue: entity.domain) else {
            return KhalaUpstreamFacts(on: nil, off: nil, serviceDomain: entity.domain, mainAction: nil)
        }
        let services = domain.toggleServices
        return KhalaUpstreamFacts(
            on: services?.on,
            off: services?.off,
            serviceDomain: domain.serviceDomain,
            mainAction: domain.mainAction(state: entity.state)
        )
    }

    /// The service call for `intent` on `entity`, or nil when the entity can't do it. A climate target is clamped
    /// to the entity's own range first (`ClimateControlState.clampTemperature`).
    static func call(for intent: KhalaIntent, entity: KhalaEntity, attributes: [String: Any]) -> KhalaServiceCall? {
        var intent = intent
        if case let .setTemperature(value) = intent, entity.domain == "climate" {
            intent = .setTemperature(ClimateControlState(state: entity.state, attributes: attributes)
                .clampTemperature(value))
        }
        return KhalaServiceTable.call(intent, entityId: entity.entityId, state: entity.state, facts: facts(for: entity))
    }
}
