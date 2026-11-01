import SwiftUI

/// A button that sends one intent of a control, asking first when the control or the entity demands it
/// (`KhalaControlModel.confirmation(for:)`): the lock hero's Unlock… and Open…, a cover's Open. The dialog sits on the
/// button itself.
struct KhalaConfirmButton: View {
    let control: KhalaControlModel
    let intent: KhalaIntent
    let title: String
    let category: KhalaAccent
    var isEnabled = true
    /// Drawn filled in the accent (the main action of a hero).
    var prominent = false
    let onIntent: (KhalaIntent) -> Void

    @State private var asking: KhalaIntent?

    var body: some View {
        let asks = control.confirmation(for: intent) != nil
        Button {
            if asks {
                asking = intent
            } else {
                onIntent(intent)
            }
        } label: {
            Text(asks ? "\(title)…" : title)
                .font(KhalaTheme.rowTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(prominent ? Color.white : KhalaTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(prominent ? KhalaTheme.accent(category) : KhalaTheme.groundFlat, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .khalaConfirmation(control, asking: $asking, wording: .question, onIntent: onIntent)
    }
}

#Preview {
    let lock = KhalaControlModel(entityId: "lock.blue_door", title: "Blue door", symbol: .sf("lock.fill"),
                                 kind: .lock(isLocked: true, canOpen: true), confirm: .unlock)
    HStack {
        KhalaConfirmButton(control: lock, intent: .unlock, title: "Unlock", category: .security, prominent: true,
                           onIntent: { _ in })
        KhalaConfirmButton(control: lock, intent: .open, title: "Open", category: .security, onIntent: { _ in })
    }
    .padding()
}
