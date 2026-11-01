import SFSafeSymbols
import SwiftUI

/// The media bottom sheet (mockup `DayTheater`) for a theater, receiver or speaker: header with the device and its
/// state, then the shared `KhalaControlGrid` in sheet style: a power switch, the big volume slider, sources in a
/// wrapping two-column grid and the sound mode as a dropdown row — each only when the player supports it
/// (`KhalaMediaLayout.controls`).
struct KhalaMediaSheet: View {
    let entityId: String
    /// The device's name (the user's), else the entity's.
    let name: String?
    @ObservedObject var live: KhalaLiveStates
    let actions: KhalaScreenActions
    let onClose: () -> Void

    var body: some View {
        Group {
            if let entity = live.entitiesById[entityId] {
                content(KhalaMediaLayout(
                    entity: entity,
                    attributes: live.attributes[entity.entityId] ?? [:],
                    name: name
                ))
            } else {
                Text(KhalaScreenText.unknownDevice)
                    .font(KhalaTheme.body)
                    .foregroundStyle(KhalaTheme.secondary)
                    .padding(24)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(40)
        .presentationBackground(.regularMaterial)
    }

    private func content(_ media: KhalaMediaLayout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(media)
                // Power, volume, sources and sound mode: the shared control grid's sheet rows, with instant feedback.
                KhalaControlGrid(
                    controls: media.controls,
                    style: .sheet,
                    category: .media,
                    pending: live.pending,
                    onIntent: { control, intent in
                        Task { await live.pending.run(intent, on: control, live: live, actions: actions) }
                    }
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
    }

    private func header(_ media: KhalaMediaLayout) -> some View {
        HStack(spacing: 12) {
            Image(systemSymbol: media.isReceiver ? .tv : .hifispeaker)
                .font(KhalaTheme.chipGlyph)
                .foregroundStyle(KhalaTheme.accent(.media))
                .frame(width: 44, height: 44)
                .background(KhalaTheme.tint(.media), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(media.name)
                    .font(KhalaTheme.sheetTitle)
                    .foregroundStyle(KhalaTheme.ink)
                    .lineLimit(1)
                Text(media.stateLine)
                    .font(KhalaTheme.sheetSubtitle)
                    .foregroundStyle(KhalaTheme.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemSymbol: .xmark)
                    .font(KhalaTheme.sectionLabel)
                    .foregroundStyle(KhalaTheme.secondary)
                    .frame(width: 36, height: 36)
                    .background(KhalaTheme.groundFlat, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(KhalaScreenText.close)
        }
    }
}
