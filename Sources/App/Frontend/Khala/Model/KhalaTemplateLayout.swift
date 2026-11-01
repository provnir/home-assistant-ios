import Foundation

/// What `KhalaTemplateScreen` shows for a device or a lone entity (DESCRIPTORS-DESIGN.md §3): the face's descriptor
/// picks the template, then the hero's controls, a group's members, tiles for the device's other controllable
/// entities, the rest as readings. The generic template is exactly the 41.1 generic screen.
struct KhalaTemplateLayout {
    /// How the hero is drawn.
    enum HeroStyle: Equatable {
        /// A kind's panel (light, fan, climate, cover, lock): its rows in one card.
        case panel
        /// The generic Power card (glyph chip, title, switch).
        case powerCard
        /// The face's own tile, one column wide.
        case tile
        /// Nothing (a sensor face, a missing entity).
        case none
    }

    let spec: KhalaTemplateSpec
    let primary: KhalaEntity?
    let subtitle: String?
    let heroStyle: HeroStyle
    let hero: [KhalaControlModel]
    let members: [KhalaControlModel]
    let controls: [KhalaControlModel]
    let readings: [KhalaEntity]

    /// Faces the generic screen draws as a Power card (41.1's set).
    static let switchable: Set<String> = ["switch", "light", "fan", "input_boolean", "automation", "siren"]

    /// - Parameters:
    ///   - powerSymbol: the generic Power card's glyph (the device's colour family's, as 41.1 draws it).
    init(
        primaryEntityId: String,
        memberEntityIds: [String],
        entities: [String: KhalaEntity],
        attributes: [String: [String: Any]],
        powerSymbol: String
    ) {
        let primary = entities[primaryEntityId]
        let faceAttributes = attributes[primaryEntityId] ?? [:]
        self.primary = primary
        let spec = primary.map { KhalaDescriptors.shown(for: $0, attributes: faceAttributes).template } ?? .generic
        self.spec = spec

        let others = memberEntityIds
            .filter { $0 != primaryEntityId }
            .compactMap { entities[$0] }
            .filter { !$0.isAuxiliary && !KhalaLabelOverride.isHidden($0) }
        let controls = others.compactMap { KhalaControlModel.tile($0, attributes: attributes[$0.entityId] ?? [:]) }
        let controlIds = Set(controls.map(\.entityId))
        self.controls = spec.sections.contains(.controls) ? controls : []
        readings = spec.sections.contains(.readings) ? others.filter { !controlIds.contains($0.entityId) } : []

        guard let primary else {
            subtitle = nil
            heroStyle = .none
            hero = []
            members = []
            return
        }
        switch spec.hero {
        case .light:
            let groupMembers = primary.groupMembers.compactMap { id in
                entities[id].map { ($0, attributes[id] ?? [:]) }
            }
            let panel = KhalaLightPanel(entity: primary, attributes: faceAttributes, members: groupMembers)
            subtitle = panel.subtitle
            heroStyle = .panel
            hero = panel.controls
            members = spec.sections.contains(.members) ? panel.members : []
        case .fan:
            let panel = KhalaFanPanel(entity: primary, attributes: faceAttributes)
            subtitle = panel.subtitle
            heroStyle = .panel
            hero = panel.controls
            members = []
        case .climate:
            let panel = KhalaClimatePanel(entity: primary, attributes: faceAttributes)
            subtitle = panel.subtitle
            heroStyle = .panel
            hero = panel.controls
            members = []
        case .cover:
            let panel = KhalaCoverPanel(entity: primary, attributes: faceAttributes)
            subtitle = panel.subtitle
            heroStyle = .panel
            hero = panel.controls
            members = []
        case .lock:
            let panel = KhalaLockPanel(entity: primary, attributes: faceAttributes)
            subtitle = panel.subtitle
            heroStyle = .panel
            hero = panel.controls
            members = []
        case .status:
            subtitle = KhalaText.stateText(for: primary)
            members = []
            if Self.switchable.contains(primary.domain) {
                heroStyle = .powerCard
                hero = [.power(primary, title: KhalaScreenText.power, symbolName: powerSymbol)]
            } else if let tile = KhalaControlModel.tile(primary, attributes: faceAttributes) {
                heroStyle = .tile
                hero = [tile]
            } else {
                heroStyle = .none
                hero = []
            }
        }
    }
}
