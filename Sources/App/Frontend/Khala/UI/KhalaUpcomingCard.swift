import SFSafeSymbols
import SwiftUI

/// Something coming later today (a scheduled automation, a device's "done at" time): glyph in a tinted circle,
/// title and subtitle on a solid card.
struct KhalaUpcomingCard: View {
    let title: String
    let subtitle: String?
    let category: KhalaCategory
    let action: (() -> Void)?

    static let height: CGFloat = 68

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(KhalaTheme.tint(category))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemSymbol: KhalaTheme.symbol(category))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(KhalaTheme.accent(category))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(KhalaTheme.cardTitle)
                        .foregroundStyle(KhalaTheme.ink)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(KhalaTheme.secondaryText)
                            .foregroundStyle(KhalaTheme.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: Self.height)
            .background(KhalaTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .khalaCardShadow()
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

#Preview {
    KhalaUpcomingCard(title: "Midnight check", subtitle: "Automation · Hot water", category: .heat, action: nil)
        .padding()
        .background(KhalaGround())
}
