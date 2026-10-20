import Foundation

/// One row of the menu's DEVICES list and one candidate chip for the Now card: a Home Assistant device (or a
/// lone entity) seen through its most telling entity.
struct KhalaDevice: Equatable, Identifiable {
    /// The registry device id, or `entity:<entity_id>` for an entity with no device.
    let id: String
    let name: String
    let category: KhalaCategory
    /// The entity whose state the row shows and whose more-info opens on tap.
    let primaryEntityId: String
    /// Short state text: "72%", "Off", "Playing", "52°".
    let stateText: String
    /// Every entity of the device, so automations that act on any of them can borrow its category.
    let memberEntityIds: [String]
    /// Placed by the user in device settings rather than detected.
    let isPinned: Bool
}
