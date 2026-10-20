import SwiftUI

/// A label/value row of an info card (settings, charging details).
struct KhalaInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(KhalaTheme.body)
                .foregroundStyle(KhalaTheme.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KhalaTheme.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    KhalaInfoRow(title: "State", value: "Idle").padding()
}
