import Shared
import SwiftUI

/// A device's or control's glyph at a given size (`KhalaIconChain`): an SF Symbol drawn in the font's point size, or
/// Home Assistant's Material Design icon, as a template, in a square matching that symbol's optical size.
struct KhalaGlyphImage: View {
    let glyph: KhalaGlyph
    let pointSize: CGFloat
    var weight: Font.Weight = .medium

    var body: some View {
        switch glyph {
        case .sf:
            KhalaTheme.image(glyph)
                .font(.system(size: pointSize, weight: weight))
        case let .mdi(name):
            let side = (pointSize * 1.3).rounded()
            Image(uiImage: MaterialDesignIcons(serversideValueNamed: name, fallback: .helpCircleIcon)
                .image(ofSize: CGSize(width: side, height: side), color: nil))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        KhalaGlyphImage(glyph: .sf("door.garage.closed"), pointSize: 17)
        KhalaGlyphImage(glyph: .mdi("mdi:gate"), pointSize: 17)
        KhalaGlyphImage(glyph: .mdi("mdi:robot-vacuum"), pointSize: 13, weight: .semibold)
    }
    .foregroundStyle(KhalaTheme.accent(.neutral))
    .padding()
}
