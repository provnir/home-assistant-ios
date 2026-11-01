import SFSafeSymbols
import SwiftUI

/// The native screen of a device without a designed screen (a relay, a plug, a pinned entity) or of a lone entity:
/// its state, a power switch when its face can be switched, tiles for whatever else can be acted on, and the rest as
/// read-only rows. Never the web more-info.
struct KhalaGenericDeviceView: View {
    let title: String
    let category: KhalaCategory
    let primaryEntityId: String
    let memberEntityIds: [String]
    @ObservedObject var live: KhalaLiveStates
    let actions: KhalaScreenActions
    let calendar: Calendar

    private static let switchable: Set<String> = ["switch", "light", "fan", "input_boolean", "automation", "siren"]

    var body: some View {
        let primary = live.entitiesById[primaryEntityId]
        let members = memberEntityIds.compactMap { live.entitiesById[$0] }.filter { !$0.isAuxiliary }
        let others = members.filter { $0.entityId != primaryEntityId }
        let controls = others.compactMap { entity in
            KhalaControl.make(entity, attributes: live.attributes[entity.entityId] ?? [:]).map {
                KhalaControlModel($0, entity: entity, attributes: live.attributes[entity.entityId] ?? [:])
            }
        }
        let controlIds = Set(controls.map(\.entityId))
        let readings = others.filter { !controlIds.contains($0.entityId) }
        KhalaDeviceScreen(
            subtitle: primary.map { KhalaText.stateText(for: $0) },
            tabs: [],
            selection: .constant(0),
            category: category,
            title: { KhalaLargeTitle(text: title) },
            trailing: { EmptyView() },
            content: {
                if let primary {
                    // The face: a Power row when it switches, else its tile; then one tile per other control.
                    if Self.switchable.contains(primary.domain) {
                        KhalaControlGrid(
                            controls: [.power(primary, title: KhalaScreenText.power,
                                              symbolName: KhalaTheme.symbol(category).rawValue)],
                            style: .card,
                            category: category,
                            pending: live.pending,
                            onIntent: run
                        )
                    } else if let control = KhalaControl.make(
                        primary,
                        attributes: live.attributes[primary.entityId] ?? [:]
                    ) {
                        KhalaControlGrid(
                            controls: [KhalaControlModel(control, entity: primary,
                                                         attributes: live.attributes[primary.entityId] ?? [:])],
                            style: .tiles(columns: 1),
                            category: category,
                            pending: live.pending,
                            onIntent: run
                        )
                    }
                    if !controls.isEmpty {
                        KhalaControlGrid(controls: controls, category: category, pending: live.pending, onIntent: run)
                            .padding(.top, 16)
                    }
                    if !readings.isEmpty {
                        KhalaSectionHeader(title: KhalaScreenText.members)
                        VStack(spacing: 0) {
                            ForEach(readings, id: \.entityId) { entity in
                                KhalaInfoRow(title: entity.nameWithoutDevice, value: KhalaText.stateText(for: entity))
                                if entity.entityId != readings.last?.entityId { Divider() }
                            }
                        }
                        .khalaCard(padding: 16)
                    }
                    let attributes = KhalaAttributeText.rows(live.attributes[primary.entityId] ?? [:])
                    KhalaSectionHeader(title: KhalaScreenText.attributes)
                    VStack(spacing: 0) {
                        KhalaInfoRow(title: KhalaScreenText.entityId, value: primary.entityId)
                        Divider()
                        KhalaInfoRow(title: KhalaScreenText.lastChanged, value: KhalaText.time(primary.lastChanged, calendar: calendar))
                        ForEach(attributes, id: \.key) { row in
                            Divider()
                            KhalaInfoRow(title: row.key, value: row.value)
                        }
                    }
                    .khalaCard(padding: 16)
                } else {
                    Text(KhalaScreenText.unknownDevice)
                        .font(KhalaTheme.body)
                        .foregroundStyle(KhalaTheme.secondary)
                }
            }
        )
    }

    private func run(_ control: KhalaControlModel, _ intent: KhalaIntent) {
        Task { await live.pending.run(intent, on: control, live: live, actions: actions) }
    }
}
