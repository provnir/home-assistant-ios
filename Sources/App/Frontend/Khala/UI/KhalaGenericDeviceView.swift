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
    let onBack: () -> Void

    private static let switchable: Set<String> = ["switch", "light", "fan", "input_boolean", "automation", "siren"]

    var body: some View {
        let primary = live.entitiesById[primaryEntityId]
        let members = memberEntityIds.compactMap { live.entitiesById[$0] }.filter { !$0.isAuxiliary }
        let others = members.filter { $0.entityId != primaryEntityId }
        let controls = others.compactMap { KhalaControl.make($0, attributes: live.attributes[$0.entityId] ?? [:]) }
        let controlIds = Set(controls.map(\.entityId))
        let readings = others.filter { !controlIds.contains($0.entityId) }
        KhalaDeviceScreen(
            subtitle: primary.map { KhalaText.stateText(for: $0) },
            tabs: [],
            selection: .constant(0),
            category: category,
            onBack: onBack,
            title: { KhalaLargeTitle(text: title) },
            trailing: { EmptyView() },
            content: {
                if let primary {
                    if Self.switchable.contains(primary.domain) {
                        let isOn = primary.state == "on"
                        HStack {
                            Image(systemSymbol: KhalaTheme.symbol(category))
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(KhalaTheme.accent(category))
                                .frame(width: 44, height: 44)
                                .background(KhalaTheme.tint(category), in: Circle())
                            Text(KhalaScreenText.power)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(KhalaTheme.ink)
                            Spacer()
                            Toggle(KhalaScreenText.power, isOn: Binding(
                                get: { isOn },
                                set: { on in Task { await actions.perform(.power(primary.entityId, on: on)) } }
                            ))
                            .labelsHidden()
                            .tint(KhalaTheme.accent(category))
                            .disabled(primary.state == "unavailable")
                        }
                        .khalaCard(padding: 14, radius: 22)
                    } else if let control = KhalaControl.make(primary, attributes: live.attributes[primary.entityId] ?? [:]) {
                        KhalaControlTile(control: control, category: category) { call in
                            Task { await actions.perform(call) }
                        }
                    }
                    if !controls.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(controls) { control in
                                KhalaControlTile(control: control, category: category) { call in
                                    Task { await actions.perform(call) }
                                }
                            }
                        }
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
}
