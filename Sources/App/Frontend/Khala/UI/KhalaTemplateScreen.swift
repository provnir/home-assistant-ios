import SFSafeSymbols
import SwiftUI

/// The template screen (DESCRIPTORS-DESIGN.md §3) of every device without a bespoke screen, and of a lone entity:
/// the face's descriptor picks the template (`KhalaTemplateLayout`). A light gets its panel — power, brightness,
/// warmth, colour as it supports them — and a group its members; a fan its panel — power, speed snapping to its
/// steps, oscillation, direction, preset; everything else (plugs, relays, pinned entities) the generic screen of
/// 41.1: a Power card when the face switches, else its tile. Then tiles for the device's other controls, the rest
/// as read-only rows, and the face's attributes. Never the web more-info. Every control runs through the one
/// `KhalaControlGrid` and `KhalaPendingStore`.
struct KhalaTemplateScreen: View {
    let title: String
    let category: KhalaCategory
    let primaryEntityId: String
    let memberEntityIds: [String]
    @ObservedObject var live: KhalaLiveStates
    let actions: KhalaScreenActions
    let calendar: Calendar
    /// Opens another entity's screen (a group member's).
    var onOpenEntity: ((String) -> Void)?

    var body: some View {
        let layout = KhalaTemplateLayout(
            primaryEntityId: primaryEntityId,
            memberEntityIds: memberEntityIds,
            entities: live.entitiesById,
            attributes: live.attributes,
            powerSymbol: KhalaTheme.symbol(category).rawValue
        )
        KhalaDeviceScreen(
            subtitle: layout.subtitle,
            tabs: [],
            selection: .constant(0),
            category: category,
            title: { KhalaLargeTitle(text: title) },
            trailing: { EmptyView() },
            content: {
                if let primary = layout.primary {
                    hero(layout)
                    if !layout.members.isEmpty {
                        KhalaSectionHeader(title: KhalaScreenText.groupMembers)
                        KhalaControlGrid(
                            controls: layout.members,
                            style: .rows,
                            category: category,
                            pending: live.pending,
                            onOpen: onOpenEntity.map { open in { open($0.entityId) } },
                            onIntent: run
                        )
                    }
                    if !layout.controls.isEmpty {
                        KhalaControlGrid(controls: layout.controls, category: category, pending: live.pending,
                                         onIntent: run)
                            .padding(.top, 16)
                    }
                    if !layout.readings.isEmpty {
                        KhalaSectionHeader(title: KhalaScreenText.members)
                        VStack(spacing: 0) {
                            ForEach(layout.readings, id: \.entityId) { entity in
                                KhalaInfoRow(title: entity.nameWithoutDevice, value: KhalaText.stateText(for: entity))
                                if entity.entityId != layout.readings.last?.entityId { Divider() }
                            }
                        }
                        .khalaCard(padding: 16)
                    }
                    if layout.spec.sections.contains(.attributes) {
                        let attributes = KhalaAttributeText.rows(live.attributes[primary.entityId] ?? [:])
                        KhalaSectionHeader(title: KhalaScreenText.attributes)
                        VStack(spacing: 0) {
                            KhalaInfoRow(title: KhalaScreenText.entityId, value: primary.entityId)
                            Divider()
                            KhalaInfoRow(
                                title: KhalaScreenText.lastChanged,
                                value: KhalaText.time(primary.lastChanged, calendar: calendar)
                            )
                            ForEach(attributes, id: \.key) { row in
                                Divider()
                                KhalaInfoRow(title: row.key, value: row.value)
                            }
                        }
                        .khalaCard(padding: 16)
                    }
                } else {
                    Text(KhalaScreenText.unknownDevice)
                        .font(KhalaTheme.body)
                        .foregroundStyle(KhalaTheme.secondary)
                }
            }
        )
    }

    @ViewBuilder
    private func hero(_ layout: KhalaTemplateLayout) -> some View {
        switch layout.heroStyle {
        case .panel:
            KhalaControlGrid(controls: layout.hero, style: .panel, category: category, pending: live.pending,
                             onIntent: run)
        case .powerCard:
            KhalaControlGrid(controls: layout.hero, style: .card, category: category, pending: live.pending,
                             onIntent: run)
        case .tile:
            KhalaControlGrid(controls: layout.hero, style: .tiles(columns: 1), category: category,
                             pending: live.pending, onIntent: run)
        case .none:
            EmptyView()
        }
    }

    private func run(_ control: KhalaControlModel, _ intent: KhalaIntent) {
        Task { await live.pending.run(intent, on: control, live: live, actions: actions) }
    }
}
