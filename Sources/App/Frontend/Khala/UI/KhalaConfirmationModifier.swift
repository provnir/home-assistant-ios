import SwiftUI

/// The confirmation dialog of a control that asks first (unlocking, opening a lock or a garage door), applied
/// directly to the trigger that raised it (a tile, a button, a position slider). The only place a
/// `KhalaIntent.confirmed` is made: `KhalaConfirmGate` refuses an unlock or an opening that arrives without one.
struct KhalaConfirmationModifier: ViewModifier {
    /// How the dialog words it.
    enum Wording {
        /// 41.1's tile words ("Unlock lock?" / "Unlock lock"), kept on every tile.
        case tile
        /// The slice-4 heroes: "Unlock blue door?" / "Unlock".
        case question
    }

    let control: KhalaControlModel
    @Binding var asking: KhalaIntent?
    var wording: Wording = .tile
    let onIntent: (KhalaIntent) -> Void
    /// The user said no (or dismissed it): a slider puts itself back.
    var onCancel: () -> Void = {}

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(
                get: { asking != nil },
                set: { presented in
                    guard !presented, asking != nil else { return }
                    asking = nil
                    onCancel()
                }
            ),
            titleVisibility: .visible,
            presenting: asking
        ) { intent in
            Button(buttonTitle) {
                asking = nil
                onIntent(.confirmed(intent))
            }
            Button(KhalaScreenText.cancel, role: .cancel) {
                asking = nil
                onCancel()
            }
        }
    }

    private var confirm: KhalaConfirm? {
        asking.flatMap { control.confirmation(for: $0) }
    }

    private var title: String {
        guard let confirm else { return control.title }
        switch wording {
        case .tile: return KhalaScreenText.confirmAction(KhalaScreenText.confirmTitle(confirm, control: control.title))
        case .question: return KhalaScreenText.confirmQuestion(confirm, name: control.title)
        }
    }

    private var buttonTitle: String {
        guard let confirm else { return control.title }
        switch wording {
        case .tile: return KhalaScreenText.confirmTitle(confirm, control: control.title)
        case .question: return KhalaScreenText.confirmButton(confirm)
        }
    }
}

extension View {
    /// Asks before `asking` goes out; see `KhalaConfirmationModifier`.
    func khalaConfirmation(
        _ control: KhalaControlModel,
        asking: Binding<KhalaIntent?>,
        wording: KhalaConfirmationModifier.Wording = .tile,
        onIntent: @escaping (KhalaIntent) -> Void,
        onCancel: @escaping () -> Void = {}
    ) -> some View {
        modifier(KhalaConfirmationModifier(control: control, asking: asking, wording: wording, onIntent: onIntent,
                                           onCancel: onCancel))
    }
}

#Preview {
    let lock = KhalaControlModel(entityId: "lock.blue_door", title: "Blue door", symbol: .sf("lock.fill"),
                                 kind: .lock(isLocked: true, canOpen: false), confirm: .unlock)
    Text("Blue door")
        .khalaConfirmation(lock, asking: .constant(.unlock), wording: .question, onIntent: { _ in })
}
