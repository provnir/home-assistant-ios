import SwiftUI

/// A section title inside a screen ("Today on Porch", "Recent", "Tonight"): 17 semibold ink.
struct KhalaSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(KhalaTheme.ink)
            .padding(.top, 26)
            .padding(.bottom, 12)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    KhalaSectionHeader(title: "Recent")
}
