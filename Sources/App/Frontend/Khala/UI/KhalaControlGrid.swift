import SFSafeSymbols
import SwiftUI

/// The one control grid (DESCRIPTORS-DESIGN.md §2): every control on the car's tabs, the generic screen and the media
/// sheet — and the light and fan panels and a group's member rows — is drawn here from `KhalaControlModel`s, with the optimistic overlay of `KhalaPendingStore` laid over each
/// so a tap shows its new state at once. A tap or pick is handed back as an intent; the screen decides how to run it
/// (the car wakes first). Controls that ask first (unlock, open) always go through a tile, whose confirmation sits
/// on its own button. `extras` are trailing tiles the screen adds (the car's Media and More).
struct KhalaControlGrid<Extras: View>: View {
    let controls: [KhalaControlModel]
    var style: KhalaControlGridStyle = .tiles(columns: 3)
    let category: KhalaCategory
    @ObservedObject var pending: KhalaPendingStore
    /// Whether `extras` draws anything; the grid shows with no controls only then.
    var hasExtras = false
    /// `.rows`: opens a row's own screen (a group member's); nil = rows don't open.
    var onOpen: ((KhalaControlModel) -> Void)?
    let onIntent: (KhalaControlModel, KhalaIntent) -> Void
    @ViewBuilder var extras: () -> Extras

    var body: some View {
        let shown = controls.map { pending.shown($0) }
        switch style {
        case let .tiles(columns):
            if !shown.isEmpty || hasExtras {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: max(1, columns)),
                          spacing: 8) {
                    ForEach(shown) { control in
                        KhalaControlTile(control: control, category: category) { onIntent(control, $0) }
                    }
                    extras()
                }
            }
        case .card:
            VStack(spacing: 8) {
                ForEach(shown) { control in
                    if let isOn = control.toggleIsOn, control.confirm == nil {
                        HStack {
                            KhalaTheme.image(control.symbol)
                                .font(KhalaTheme.chipGlyph)
                                .foregroundStyle(KhalaTheme.accent(category))
                                .frame(width: 44, height: 44)
                                .background(KhalaTheme.tint(category), in: Circle())
                            Text(control.title)
                                .font(KhalaTheme.rowTitle)
                                .foregroundStyle(KhalaTheme.ink)
                            Spacer()
                            Toggle(control.title, isOn: Binding(
                                get: { isOn },
                                set: { onIntent(control, .setOn($0)) }
                            ))
                            .labelsHidden()
                            .tint(KhalaTheme.accent(category))
                            .disabled(!control.isAvailable)
                        }
                        .khalaCard(padding: 14, radius: 22)
                    } else {
                        KhalaControlTile(control: control, category: category) { onIntent(control, $0) }
                    }
                }
            }
        case .panel:
            if !shown.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(shown) { control in
                        KhalaPanelRow(control: control, category: category) { onIntent(control, $0) }
                        if control.id != shown.last?.id { Divider() }
                    }
                }
                .khalaCard(padding: 14, radius: 22)
            }
        case .rows:
            if !shown.isEmpty {
                VStack(spacing: 0) {
                    ForEach(shown) { control in
                        KhalaMemberRow(
                            control: control,
                            category: category,
                            onIntent: { onIntent(control, $0) },
                            onOpen: onOpen.map { open in { open(control) } }
                        )
                        if control.id != shown.last?.id { Divider() }
                    }
                }
                .khalaCard(padding: 14, radius: 22)
            }
        case .sheet:
            VStack(alignment: .leading, spacing: 18) {
                ForEach(shown) { control in
                    switch control.kind {
                    case let .toggle(isOn) where control.confirm == nil:
                        HStack {
                            Text(control.title)
                                .font(KhalaTheme.rowTitle)
                                .foregroundStyle(KhalaTheme.ink)
                            Spacer()
                            Toggle(control.title, isOn: Binding(
                                get: { isOn },
                                set: { onIntent(control, .setOn($0)) }
                            ))
                            .labelsHidden()
                            .tint(KhalaTheme.accent(category))
                            .disabled(!control.isAvailable)
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, 12)
                        .frame(height: 56)
                        .background(KhalaTheme.groundFlat, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    case let .slider(slider, value):
                        // Volume is 0...1 as HA reports it; the other sliders 0...100.
                        let scale = slider == .volume ? 1.0 : 100.0
                        let level = (value ?? 0) / scale
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(control.title)
                                    .font(KhalaTheme.sectionLabel)
                                    .kerning(1)
                                    .foregroundStyle(KhalaTheme.muted)
                                Spacer()
                                Text(KhalaMediaLayout.volumeText(level))
                                    .font(KhalaTheme.rowValue)
                                    .monospacedDigit()
                                    .foregroundStyle(KhalaTheme.ink)
                            }
                            KhalaVolumeSlider(level: level) { onIntent(control, .set(slider, $0 * scale)) }
                        }
                    case let .choice(current, options, .source):
                        VStack(alignment: .leading, spacing: 10) {
                            Text(control.title)
                                .font(KhalaTheme.sectionLabel)
                                .kerning(1)
                                .foregroundStyle(KhalaTheme.muted)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                                      spacing: 8) {
                                ForEach(options, id: \.self) { option in
                                    let isSelected = option == current
                                    Button {
                                        onIntent(control, .choose(.source, option))
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemSymbol: .playFill)
                                                .font(KhalaTheme.rowGlyph)
                                            Text(option)
                                                .font(KhalaTheme.rowValue)
                                                .lineLimit(2)
                                                .minimumScaleFactor(0.8)
                                            Spacer(minLength: 0)
                                        }
                                        .foregroundStyle(isSelected ? KhalaTheme.accent(category) : KhalaTheme.ink)
                                        .padding(.horizontal, 14)
                                        .frame(height: 56)
                                        .background(
                                            isSelected ? KhalaTheme.tint(category) : KhalaTheme.groundFlat,
                                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .strokeBorder(isSelected ? KhalaTheme.accent(category) : Color.clear,
                                                              lineWidth: 1.5)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                                }
                            }
                        }
                    case let .choice(current, options, field):
                        Menu {
                            ForEach(options, id: \.self) { option in
                                Button {
                                    onIntent(control, .choose(field, option))
                                } label: {
                                    if option == current {
                                        Label(option, systemSymbol: .checkmark)
                                    } else {
                                        Text(option)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text(control.title)
                                    .font(KhalaTheme.rowTitle)
                                    .foregroundStyle(KhalaTheme.ink)
                                Spacer()
                                Text(current ?? "—")
                                    .font(KhalaTheme.rowTitle)
                                    .foregroundStyle(KhalaTheme.accent(category))
                                    .lineLimit(1)
                                Image(systemSymbol: .chevronUpChevronDown)
                                    .font(KhalaTheme.smallGlyph)
                                    .foregroundStyle(KhalaTheme.accent(category))
                            }
                            .padding(.leading, 16)
                            .padding(.trailing, 14)
                            .frame(height: 56)
                            .background(KhalaTheme.groundFlat,
                                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .disabled(!control.isEnabled)
                    default:
                        KhalaControlTile(control: control, category: category) { onIntent(control, $0) }
                    }
                }
            }
        }
    }
}

extension KhalaControlGrid where Extras == EmptyView {
    init(
        controls: [KhalaControlModel],
        style: KhalaControlGridStyle = .tiles(columns: 3),
        category: KhalaCategory,
        pending: KhalaPendingStore,
        onOpen: ((KhalaControlModel) -> Void)? = nil,
        onIntent: @escaping (KhalaControlModel, KhalaIntent) -> Void
    ) {
        self.init(controls: controls, style: style, category: category, pending: pending, hasExtras: false,
                  onOpen: onOpen, onIntent: onIntent, extras: { EmptyView() })
    }
}

#Preview {
    let pending = KhalaPendingStore()
    return ScrollView {
        VStack(spacing: 24) {
            KhalaControlGrid(
                controls: [
                    KhalaControlModel(entityId: "switch.sentry", title: "Sentry mode", symbol: .sf("shield.fill"),
                                      kind: .toggle(isOn: true), confirm: nil),
                    KhalaControlModel(entityId: "button.flash", title: "Flash lights", symbol: .sf("lightbulb.fill"),
                                      kind: .press, confirm: nil),
                    KhalaControlModel(entityId: "select.seat", title: "Seat heater", symbol: .sf("flame.fill"),
                                      kind: .choice(current: "low", options: ["off", "low", "high"], field: .option),
                                      confirm: nil),
                ],
                category: .car,
                pending: pending,
                onIntent: { _, _ in }
            )
            KhalaControlGrid(
                controls: [
                    KhalaControlModel(entityId: "media_player.den", title: "Power", symbol: .sf("power"),
                                      kind: .toggle(isOn: true), confirm: nil),
                    KhalaControlModel(entityId: "media_player.den", title: "VOLUME", symbol: .sf("speaker.wave.2.fill"),
                                      kind: .slider(.volume, value: 0.4), confirm: nil),
                    KhalaControlModel(entityId: "media_player.den", title: "SOURCE", symbol: .sf("play.fill"),
                                      kind: .choice(current: "Music", options: ["Music", "Console"], field: .source),
                                      confirm: nil),
                ],
                style: .sheet,
                category: .media,
                pending: pending,
                onIntent: { _, _ in }
            )
        }
        .padding()
    }
    .background(KhalaGround())
}
