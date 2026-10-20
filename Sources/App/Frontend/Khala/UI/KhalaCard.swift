import SwiftUI

extension View {
    /// A solid content platter (DESIGN.md "card"): white, radius 28, the card shadow.
    func khalaCard(padding: CGFloat = 18, radius: CGFloat = 28) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KhalaTheme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .khalaCardShadow()
    }
}
