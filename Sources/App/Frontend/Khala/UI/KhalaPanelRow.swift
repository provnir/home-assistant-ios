import SFSafeSymbols
import SwiftUI

/// One row of a kind's panel (`KhalaControlGridStyle.panel`, DESCRIPTORS-DESIGN.md §3): a power or oscillation
/// switch beside its glyph chip, a slider under its title and value, a choice as a dropdown (never a side-scroller),
/// a colour as the system picker, a climate target as the large − value + stepper (300 ms debounce), a lock's state
/// with Lock / Unlock…, and command buttons (a cover's Open / Stop / Close, a lock's Open…). Whatever asks first
/// asks on its own trigger (`KhalaConfirmationModifier`); anything else falls back to its tile.
struct KhalaPanelRow: View {
    let control: KhalaControlModel
    let category: KhalaCategory
    let onIntent: (KhalaIntent) -> Void

    /// A slider value waiting for its confirmation (a garage door's position above where it is).
    @State private var asking: KhalaIntent?
    /// Bumped when a confirmation is declined, so the slider lets go of the value it was dragged to.
    @State private var declined = 0

    var body: some View {
        switch control.kind {
        case let .toggle(isOn) where !control.asksFirst:
            switchRow(isOn: isOn) { onIntent(.setOn($0)) }
        case let .flag(flag, isOn):
            switchRow(isOn: isOn) { onIntent(.setFlag(flag, $0)) }
        case let .slider(slider, value):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(control.title)
                        .font(KhalaTheme.rowTitle)
                        .foregroundStyle(KhalaTheme.ink)
                    Spacer()
                    Text(value.map(slider.text) ?? "—")
                        .font(KhalaTheme.rowValue)
                        .monospacedDigit()
                        .foregroundStyle(KhalaTheme.secondary)
                }
                KhalaLevelSlider(slider: slider, value: value, symbol: control.symbol, category: category,
                                 title: control.title, isEnabled: control.isEnabled) { picked in
                    let intent = KhalaIntent.set(slider, picked)
                    if control.confirmation(for: intent) != nil {
                        asking = intent
                    } else {
                        onIntent(intent)
                    }
                }
                .id(declined)
                .khalaConfirmation(control, asking: $asking, wording: .question, onIntent: onIntent,
                                   onCancel: { declined += 1 })
            }
            .padding(.vertical, 6)
        case let .stepper(setting):
            VStack(spacing: 8) {
                KhalaNumberStepper(setting: setting, category: category, large: true) { value in
                    if let intent = control.valueIntent(value) { onIntent(intent) }
                }
                .disabled(!control.isAvailable)
                .opacity(control.isAvailable ? 1 : 0.45)
            }
            .padding(.vertical, 6)
        case .lock:
            HStack(spacing: 12) {
                glyphChip
                VStack(alignment: .leading, spacing: 2) {
                    Text(control.stateText)
                        .font(KhalaTheme.rowTitle)
                        .foregroundStyle(KhalaTheme.ink)
                }
                Spacer(minLength: 8)
                let intent = control.tapIntent ?? .lock
                KhalaConfirmButton(
                    control: control,
                    intent: intent,
                    title: intent == .unlock ? KhalaScreenText.unlock : KhalaScreenText.lock,
                    category: category,
                    isEnabled: control.tapIntent != nil,
                    prominent: true,
                    onIntent: onIntent
                )
                .frame(maxWidth: 160)
            }
        case let .commands(commands):
            HStack(spacing: 8) {
                if commands.contains(where: \.isTilt) {
                    Text(control.title)
                        .font(KhalaTheme.rowTitle)
                        .foregroundStyle(KhalaTheme.ink)
                    Spacer(minLength: 8)
                }
                ForEach(commands, id: \.self) { command in
                    KhalaConfirmButton(
                        control: control,
                        intent: .command(command),
                        title: KhalaScreenText.command(command),
                        category: category,
                        isEnabled: control.isEnabled(command),
                        onIntent: onIntent
                    )
                }
            }
        case let .choice(current, options, field):
            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        onIntent(.choose(field, option))
                    } label: {
                        if option == current {
                            Label(KhalaText.humanized(state: option), systemSymbol: .checkmark)
                        } else {
                            Text(KhalaText.humanized(state: option))
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(control.title)
                        .font(KhalaTheme.rowTitle)
                        .foregroundStyle(KhalaTheme.ink)
                    Spacer()
                    Text(current.map { KhalaText.humanized(state: $0) } ?? "—")
                        .font(KhalaTheme.rowValue)
                        .foregroundStyle(KhalaTheme.accent(category))
                        .lineLimit(1)
                    Image(systemSymbol: .chevronUpChevronDown)
                        .font(KhalaTheme.smallGlyph)
                        .foregroundStyle(KhalaTheme.accent(category))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .disabled(!control.isEnabled)
        case .color:
            KhalaColorControl(control: control, category: category, onIntent: onIntent)
                .frame(minHeight: 44)
        default:
            KhalaControlTile(control: control, category: category, onIntent: onIntent)
        }
    }

    private var glyphChip: some View {
        KhalaTheme.image(control.symbol)
            .font(KhalaTheme.chipGlyph)
            .foregroundStyle(KhalaTheme.accent(category))
            .frame(width: 44, height: 44)
            .background(KhalaTheme.tint(category), in: Circle())
    }

    private func switchRow(isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 12) {
            glyphChip
            Text(control.title)
                .font(KhalaTheme.rowTitle)
                .foregroundStyle(KhalaTheme.ink)
            Spacer()
            Toggle(control.title, isOn: Binding(get: { isOn }, set: set))
                .labelsHidden()
                .tint(KhalaTheme.accent(category))
                .disabled(!control.isAvailable)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        KhalaPanelRow(
            control: KhalaControlModel(entityId: "light.desk", title: "Power", symbol: .sf("lightbulb.fill"),
                                       kind: .toggle(isOn: true), confirm: nil),
            category: .sun,
            onIntent: { _ in }
        )
        KhalaPanelRow(
            control: KhalaControlModel(entityId: "light.desk", title: "Brightness", symbol: .sf("sun.max.fill"),
                                       kind: .slider(.brightness, value: 70), confirm: nil),
            category: .sun,
            onIntent: { _ in }
        )
    }
    .khalaCard(padding: 14, radius: 22)
    .padding()
    .background(KhalaGround())
}
