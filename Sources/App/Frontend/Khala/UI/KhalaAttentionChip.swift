import SwiftUI

/// The amber "needs attention" chip (mockup `DaySettings`: pending updates, open repairs): heat's tint as the
/// ground, an amber dot, amber ink.
struct KhalaAttentionChip: View {
    let text: String
    var showsDot = true
    var height: CGFloat = 28

    var body: some View {
        HStack(spacing: 5) {
            if showsDot {
                Circle()
                    .fill(KhalaTheme.accent(.heat))
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(KhalaTheme.attentionInk)
                .lineLimit(1)
        }
        .padding(.horizontal, height >= 28 ? 10 : 8)
        .frame(height: height)
        .background(KhalaTheme.tint(.heat), in: Capsule())
    }
}

#Preview {
    VStack {
        KhalaAttentionChip(text: "1 update")
        KhalaAttentionChip(text: "2 repairs", showsDot: false, height: 22)
    }
}
