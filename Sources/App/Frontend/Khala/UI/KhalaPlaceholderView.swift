import SwiftUI

/// A destination whose native screen isn't built yet: says so and offers the web UI's page for it.
struct KhalaPlaceholderView: View {
    let title: String
    let message: String
    let actionTitle: String
    let onMenu: () -> Void
    let action: () -> Void

    var body: some View {
        KhalaScreen(title: title, subtitle: nil, onMenu: onMenu) {
            VStack(alignment: .leading, spacing: 16) {
                Text(message)
                    .font(KhalaTheme.body)
                    .foregroundStyle(KhalaTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: action) {
                    Text(actionTitle)
                        .font(KhalaTheme.cardTitle)
                        .foregroundStyle(KhalaTheme.ink)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(KhalaTheme.card, in: Capsule())
                        .khalaCardShadow()
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KhalaTheme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

#Preview {
    KhalaPlaceholderView(
        title: KhalaText.automations,
        message: KhalaText.automationsPending,
        actionTitle: KhalaText.openAutomations,
        onMenu: {},
        action: {}
    )
    .background(KhalaGround())
}
