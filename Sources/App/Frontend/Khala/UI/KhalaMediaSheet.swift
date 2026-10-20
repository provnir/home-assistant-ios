import SFSafeSymbols
import SwiftUI

/// The media bottom sheet (mockup `DayTheater`) for a theater, receiver or speaker: header with the device and its
/// state, a power switch, the big volume slider, sources in a wrapping two-column grid, and the sound mode as a
/// dropdown row — each only when the player supports it (`KhalaMediaLayout`).
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
                if media.canPower {
                    HStack {
                        Text(KhalaScreenText.power)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(KhalaTheme.ink)
                        Spacer()
                        Toggle(KhalaScreenText.power, isOn: Binding(
                            get: { media.isOn },
                            set: { on in perform(media.power(on: on)) }
                        ))
                        .labelsHidden()
                        .tint(KhalaTheme.accent(.media))
                        .disabled(media.isUnavailable)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 12)
                    .frame(height: 56)
                    .background(KhalaTheme.groundFlat, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                if let volume = media.volume, media.isOn {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            sectionTitle(KhalaScreenText.volume)
                            Spacer()
                            Text(KhalaMediaLayout.volumeText(volume))
                                .font(.system(size: 15, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(KhalaTheme.ink)
                        }
                        KhalaVolumeSlider(level: volume) { level in perform(media.setVolume(level)) }
                    }
                }
                if !media.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle(KhalaScreenText.source)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                                  spacing: 8) {
                            ForEach(media.sources, id: \.self) { source in
                                sourceButton(source, media: media)
                            }
                        }
                    }
                }
                if !media.soundModes.isEmpty {
                    Menu {
                        ForEach(media.soundModes, id: \.self) { mode in
                            Button {
                                perform(media.selectSoundMode(mode))
                            } label: {
                                if mode == media.soundMode {
                                    Label(mode, systemSymbol: .checkmark)
                                } else {
                                    Text(mode)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(KhalaScreenText.soundMode)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(KhalaTheme.ink)
                            Spacer()
                            Text(media.soundMode ?? "—")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(KhalaTheme.accent(.media))
                                .lineLimit(1)
                            Image(systemSymbol: .chevronUpChevronDown)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(KhalaTheme.accent(.media))
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, 14)
                        .frame(height: 56)
                        .background(KhalaTheme.groundFlat, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .disabled(!media.isOn)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
    }

    private func header(_ media: KhalaMediaLayout) -> some View {
        HStack(spacing: 12) {
            Image(systemSymbol: media.isReceiver ? .tv : .hifispeaker)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(KhalaTheme.accent(.media))
                .frame(width: 44, height: 44)
                .background(KhalaTheme.tint(.media), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(media.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(KhalaTheme.ink)
                    .lineLimit(1)
                Text(media.stateLine)
                    .font(.system(size: 14))
                    .foregroundStyle(KhalaTheme.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemSymbol: .xmark)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(KhalaTheme.secondary)
                    .frame(width: 36, height: 36)
                    .background(KhalaTheme.groundFlat, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(KhalaScreenText.close)
        }
    }

    private func sourceButton(_ source: String, media: KhalaMediaLayout) -> some View {
        let isSelected = media.isOn && source == media.source
        return Button {
            perform(media.selectSource(source))
        } label: {
            HStack(spacing: 10) {
                Image(systemSymbol: .playFill)
                    .font(.system(size: 14, weight: .semibold))
                Text(source)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? KhalaTheme.accent(.media) : KhalaTheme.ink)
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(
                isSelected ? KhalaTheme.tint(.media) : KhalaTheme.groundFlat,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? KhalaTheme.accent(.media) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .kerning(1)
            .foregroundStyle(KhalaTheme.muted)
    }

    private func perform(_ call: KhalaServiceCall) {
        Task { await actions.perform(call) }
    }
}
