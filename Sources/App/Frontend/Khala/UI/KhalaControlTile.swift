import SFSafeSymbols
import SwiftUI

/// A 76 pt tile of `KhalaControlGrid` (mockup `DayCar`): glyph over a short label, tinted in the screen's accent while
/// active (locked, on, open), white otherwise. It shows its model as given — the grid lays any pending value over
/// it first — and reports what a tap asks for as a `KhalaIntent`. Unlocking and opening ask first; a choice offers
/// its options as a pull-down (a vertical list, never a side-scroller).
struct KhalaControlTile: View {
    let control: KhalaControlModel
    let category: KhalaCategory
    let onIntent: (KhalaIntent) -> Void

    @State private var asking: KhalaIntent?

    var body: some View {
        let active = control.isActive
        let tint = active ? KhalaTheme.accent(category) : KhalaTheme.ink
        // Locks read as their state ("Locked"); a choice as its name over its state; the rest by name.
        let label: String = {
            switch control.kind {
            case .lock: return control.stateText
            case .choice: return "\(control.title)\n\(control.stateText)"
            default: return control.title
            }
        }()
        let face = VStack(spacing: 6) {
            KhalaTheme.image(control.symbol)
                .font(KhalaTheme.tileGlyph)
                .foregroundStyle(tint)
            Text(label)
                .font(KhalaTheme.tileLabel)
                .foregroundStyle(tint)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(
            active ? KhalaTheme.tint(category) : KhalaTheme.card,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .modify { view in
            if active { view } else { view.khalaCardShadow() }
        }
        .opacity(control.isEnabled ? 1 : 0.45)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(control.stateText)
        .animation(.easeOut(duration: 0.15), value: active)

        if case let .choice(current, options, field) = control.kind {
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
                face
            }
            .disabled(!control.isEnabled)
        } else {
            Button {
                guard let intent = control.tapIntent else { return }
                if control.confirmation(for: intent) != nil {
                    asking = intent
                } else {
                    onIntent(intent)
                }
            } label: {
                face
            }
            .buttonStyle(.plain)
            .disabled(control.tapIntent == nil)
            .confirmationDialog(
                KhalaScreenText.confirmAction(confirmTitle),
                isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                titleVisibility: .visible,
                presenting: asking
            ) { intent in
                Button(confirmTitle) { onIntent(intent) }
                Button(KhalaScreenText.cancel, role: .cancel) {}
            }
        }
    }

    /// "Unlock lock", "Open charge port door" (41.1's words), else the control's name.
    private var confirmTitle: String {
        guard let intent = asking ?? control.tapIntent, let confirm = control.confirmation(for: intent) else {
            return control.title
        }
        return KhalaScreenText.confirmTitle(confirm, control: control.title)
    }
}

#Preview {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
        KhalaControlTile(
            control: {
                var lock = KhalaControlModel(entityId: "lock.rover", title: "Lock", symbol: .sf("lock.fill"),
                                             kind: .lock(isLocked: true, canOpen: false), confirm: .unlock)
                lock.stateText = "Locked"
                return lock
            }(),
            category: .car,
            onIntent: { _ in }
        )
        KhalaControlTile(
            control: KhalaControlModel(entityId: "button.flash", title: "Flash lights", symbol: .sf("lightbulb.fill"),
                                       kind: .press, confirm: nil),
            category: .car,
            onIntent: { _ in }
        )
    }
    .padding()
    .background(KhalaGround())
}
