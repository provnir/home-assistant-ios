import SwiftUI

/// A group member's row (`KhalaControlGridStyle.rows`, mockup "Light group" MEMBERS): glyph chip, name and state
/// open the member's own screen; the switch turns just that member on or off.
struct KhalaMemberRow: View {
    let control: KhalaControlModel
    let category: KhalaCategory
    let onIntent: (KhalaIntent) -> Void
    let onOpen: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onOpen?()
            } label: {
                HStack(spacing: 12) {
                    KhalaTheme.image(control.symbol)
                        .font(KhalaTheme.rowGlyph)
                        .foregroundStyle(control.isActive ? KhalaTheme.accent(category) : KhalaTheme.secondary)
                        .frame(width: 32, height: 32)
                        .background(control.isActive ? KhalaTheme.tint(category) : KhalaTheme.groundFlat,
                                    in: Circle())
                    Text(control.title)
                        .font(KhalaTheme.rowTitle)
                        .foregroundStyle(KhalaTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(control.stateText)
                        .font(KhalaTheme.rowValue)
                        .monospacedDigit()
                        .foregroundStyle(KhalaTheme.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onOpen == nil)
            // A member that asks first (a lock, a garage door) is opened, never switched from a row.
            if let isOn = control.toggleIsOn, !control.asksFirst {
                Toggle(control.title, isOn: Binding(get: { isOn }, set: { onIntent(.setOn($0)) }))
                    .labelsHidden()
                    .tint(KhalaTheme.accent(category))
                    .disabled(!control.isAvailable)
            }
        }
        .frame(minHeight: 48)
    }
}

#Preview {
    KhalaMemberRow(
        control: {
            var row = KhalaControlModel(entityId: "light.ceiling", title: "Ceiling", symbol: .sf("lightbulb.fill"),
                                        kind: .toggle(isOn: true), confirm: nil)
            row.stateText = "80%"
            return row
        }(),
        category: .sun,
        onIntent: { _ in },
        onOpen: {}
    )
    .khalaCard(padding: 14, radius: 22)
    .padding()
}
