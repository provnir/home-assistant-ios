import Foundation
import Shared

/// The lock hero (DESCRIPTORS-DESIGN.md §3, "Lock"): the lock itself — Lock, or Unlock… which always asks — and,
/// when the lock can pull its latch (`LockCapabilities.supportsOpen`, "the lock open gate"), Open…, which always asks
/// too. While Home Assistant doesn't know the state (unknown, unavailable) nothing can be sent, as on the car.
struct KhalaLockPanel: Equatable {
    let entityId: String
    /// "Locked", "Unlocked", "Jammed".
    let subtitle: String
    /// The lock, then Open when supported.
    let controls: [KhalaControlModel]

    init(entity: KhalaEntity, attributes: [String: Any]) {
        let canOpen = LockCapabilities(attributes: attributes).supportsOpen
        let known = !["unknown", "unavailable", ""].contains(entity.state)
        let locked = entity.state == "locked"
        entityId = entity.entityId

        // Titled with the lock's own name, so the question reads "Unlock front door?".
        var lock = KhalaControlModel(entityId: entity.entityId, title: entity.name,
                                     symbol: .sf(locked || !known ? KhalaControl.Glyph.lock.symbolName
                                         : KhalaControl.Glyph.unlock.symbolName),
                                     kind: .lock(isLocked: locked, canOpen: canOpen), confirm: .unlock)
        lock.stateText = known ? KhalaText.humanized(state: entity.state) : KhalaControl.unknownStateText
        lock.isAvailable = known
        lock.deviceClass = entity.deviceClass
        var controls = [lock]
        if canOpen {
            var open = KhalaControlModel(entityId: entity.entityId, title: entity.name, symbol: .sf("door.left.hand.open"),
                                         kind: .commands([.open]), confirm: .open(deviceClass: entity.deviceClass))
            open.isAvailable = known
            open.deviceClass = entity.deviceClass
            controls.append(open)
        }
        self.controls = controls
        subtitle = KhalaText.humanized(state: entity.state)
    }
}
