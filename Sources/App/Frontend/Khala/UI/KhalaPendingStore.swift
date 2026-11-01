import Foundation
import Shared

/// The optimistic overlay of every control on screen (DESCRIPTORS-DESIGN.md §2), kept next to the live states it
/// is checked against (`KhalaLiveStates.pending`). The rules are `KhalaPendingBook`'s; this store runs a control's
/// intent through them: show it at once, refuse a double-fire, optionally prepare (a car wakes first), send it
/// through `KhalaUpstreamBridge`, then settle on the real state — on its echo, on a refusal (with the error
/// haptic `KhalaScreenActions.perform` plays) or after the echo timeout.
@MainActor
final class KhalaPendingStore: ObservableObject {
    @Published private(set) var book = KhalaPendingBook()
    private var expiryTask: Task<Void, Never>?

    /// `model` as it should look right now.
    func shown(_ model: KhalaControlModel) -> KhalaControlModel {
        model.showing(book.pending(model.id))
    }

    /// Checks the pending entries against fresh live states (`KhalaLiveStates.update`).
    func reconcile(entities: [String: KhalaEntity], attributes: [String: [String: Any]]) {
        guard !book.entries.isEmpty else { return }
        var next = book
        if next.reconcile(entities: entities, attributes: attributes, now: Current.date()) {
            book = next
        }
        scheduleExpiry()
    }

    /// Runs `intent` on `model`. `prepare` runs after the control already shows the new state and before the call
    /// (the car's wake); false from it reverts. True when Home Assistant accepted the call.
    @discardableResult
    func run(
        _ intent: KhalaIntent,
        on model: KhalaControlModel,
        live: KhalaLiveStates,
        actions: KhalaScreenActions,
        prepare: (() async -> Bool)? = nil
    ) async -> Bool {
        guard let entity = live.entitiesById[model.entityId],
              let call = KhalaUpstreamBridge.call(
                  for: intent,
                  on: model,
                  entity: entity,
                  attributes: live.attributes[model.entityId] ?? [:]
              ) else {
            // No service, or an unlock / opening without its confirmation (`KhalaConfirmGate`).
            Current.Log.info("Khala: no service for \(intent) on \(model.entityId)")
            return false
        }
        let started = Current.date()
        if let pending = model.pendingValue(for: intent) {
            // A double-fire (same control, still out or within the throttle) is dropped silently.
            guard book.begin(model.id, entityId: model.entityId, value: pending.value, echo: pending.echo,
                             now: started) else { return false }
        }
        if let prepare {
            let ready = await prepare()
            guard ready else {
                book.answer(model.id, startedAt: started, ok: false, now: Current.date())
                return false
            }
        }
        let ok = await actions.perform(call)
        book.answer(model.id, startedAt: started, ok: ok, now: Current.date())
        scheduleExpiry()
        return ok
    }

    /// Wakes when the next entry runs out so a value whose echo never came steps aside on time.
    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let next = book.nextExpiry else { return }
        let delay = max(0, next.timeIntervalSince(Current.date())) + 0.05
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            var next = book
            next.expire(now: Current.date())
            if next != book { book = next }
            scheduleExpiry()
        }
    }
}
