import Foundation

/// One row of the menu's DEVICES list and one candidate chip for the Now card: a Home Assistant device (or a
/// lone entity) seen through its most telling entity.
struct KhalaDevice: Equatable, Identifiable {
    /// The registry device id, or `entity:<entity_id>` for an entity with no device.
    let id: String
    let name: String
    /// What the device is (car, water heater, media, switch…).
    let kind: KhalaKind
    /// Its colour family: the kind's own, or the role the user picked when pinning it.
    let accent: KhalaAccent
    /// The entity whose state the row shows and whose more-info opens on tap.
    let primaryEntityId: String
    /// Short state text: "72%", "Off", "Playing", "52°".
    let stateText: String
    /// Every entity of the device, so automations that act on any of them can borrow its category.
    let memberEntityIds: [String]
    /// Placed by the user in device settings rather than detected.
    let isPinned: Bool
    /// The Home Assistant area of its face entity (for grouping the menu by area, decision 1), when known.
    let areaId: String?
    /// Its glyph in the menu and on the Now card (`KhalaIconChain.device`); the kind's fallback symbol when built
    /// without a face entity (previews).
    let glyph: KhalaGlyph

    /// The colour family under its pre-descriptor name; screens and routing still switch on it in slice 1.
    var category: KhalaCategory { accent }

    init(
        id: String,
        name: String,
        kind: KhalaKind,
        accent: KhalaAccent? = nil,
        primaryEntityId: String,
        stateText: String,
        memberEntityIds: [String],
        isPinned: Bool,
        areaId: String? = nil,
        glyph: KhalaGlyph? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.accent = accent ?? kind.accent
        self.primaryEntityId = primaryEntityId
        self.stateText = stateText
        self.memberEntityIds = memberEntityIds
        self.isPinned = isPinned
        self.areaId = areaId
        self.glyph = glyph ?? .sf(kind.descriptor.fallbackSymbol)
    }

    /// A device from a legacy category (previews, older call sites): the kind is the one that role stands for on
    /// the primary entity's domain, and the accent is the category itself.
    init(
        id: String,
        name: String,
        category: KhalaCategory,
        primaryEntityId: String,
        stateText: String,
        memberEntityIds: [String],
        isPinned: Bool
    ) {
        let domain = primaryEntityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? primaryEntityId
        self.init(
            id: id,
            name: name,
            kind: category.kind(forDomain: domain),
            accent: category,
            primaryEntityId: primaryEntityId,
            stateText: stateText,
            memberEntityIds: memberEntityIds,
            isPinned: isPinned
        )
    }
}
