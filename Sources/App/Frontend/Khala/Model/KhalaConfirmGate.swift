import Foundation

/// The one way from a control's intent to a service call (DESCRIPTORS-DESIGN.md §2 and §4, slice 4): it asks the
/// control what it declares (`KhalaControlModel.confirmation(for:)`) AND the entity's own data (`KhalaConfirmPolicy`),
/// and refuses an intent that needs a confirmation and arrives without one (`KhalaIntent.confirmed`, made only by the
/// confirmation dialog). Only then does `KhalaServiceTable` turn it into a call. `KhalaUpstreamBridge` (iOS) supplies
/// the upstream facts and is the only caller; nothing else reaches the table.
enum KhalaConfirmGate {
    /// The question `intent` on `control` must be confirmed with, or nil.
    static func confirmation(
        for intent: KhalaIntent,
        on control: KhalaControlModel,
        entity: KhalaEntity,
        attributes: [String: Any]
    ) -> KhalaConfirm? {
        control.confirmation(for: intent) ?? KhalaConfirmPolicy.required(
            intent,
            domain: entity.domain,
            deviceClass: entity.deviceClass,
            position: KhalaValue.double(attributes["current_position"])
        )
    }

    /// The call for `intent`, or nil when it needs a confirmation it doesn't carry, the control belongs to another
    /// entity, or the entity can't do it.
    static func call(
        _ intent: KhalaIntent,
        on control: KhalaControlModel,
        entity: KhalaEntity,
        attributes: [String: Any],
        facts: KhalaUpstreamFacts
    ) -> KhalaServiceCall? {
        guard control.entityId == entity.entityId else { return nil }
        if confirmation(for: intent, on: control, entity: entity, attributes: attributes) != nil,
           !intent.isConfirmed {
            return nil
        }
        return KhalaServiceTable.call(intent.unconfirmed, entityId: entity.entityId, state: entity.state,
                                      facts: facts)
    }
}
