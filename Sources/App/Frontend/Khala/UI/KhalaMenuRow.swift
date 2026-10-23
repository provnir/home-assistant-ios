import SFSafeSymbols
import SwiftUI
import UIKit

/// A 48 pt row of the Khala menu: a destination (plain glyph), a dashboard or a device (glyph in a tinted circle).
/// The selected destination sits on a white platter.
struct KhalaMenuRow: View {
    let title: String
    let symbol: SFSymbol
    let symbolColor: Color
    /// When set, the glyph sits in a 28 pt circle of this colour (device rows).
    var chipTint: Color?
    /// Drawn instead of `symbol` when set (a dashboard's Material Design icon from Home Assistant), as a template
    /// in `symbolColor`.
    var image: UIImage?
    var trailing: String?
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let chipTint {
                    Circle()
                        .fill(chipTint)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemSymbol: symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(symbolColor)
                        )
                } else if let image {
                    Image(uiImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(symbolColor)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemSymbol: symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(symbolColor)
                        .frame(width: 22)
                }
                Text(title)
                    .font(isSelected ? KhalaTheme.menuRowSelected : KhalaTheme.menuRow)
                    .foregroundStyle(KhalaTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(KhalaTheme.menuTrailing)
                        .foregroundStyle(KhalaTheme.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(KhalaTheme.card)
                        .shadow(color: KhalaTheme.shadow.opacity(0.06), radius: 1, x: 0, y: 1)
                        .shadow(color: KhalaTheme.shadow.opacity(0.06), radius: 8, x: 0, y: 6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VStack(spacing: 2) {
        KhalaMenuRow(title: KhalaText.today, symbol: .textAlignleft, symbolColor: KhalaTheme.ink, isSelected: true) {}
        KhalaMenuRow(
            title: KhalaText.cameras,
            symbol: .video,
            symbolColor: KhalaTheme.accent(.security),
            trailing: "8"
        ) {}
        KhalaMenuRow(
            title: "Hot water",
            symbol: .drop,
            symbolColor: KhalaTheme.accent(.heat),
            chipTint: KhalaTheme.tint(.heat),
            trailing: "Off"
        ) {}
    }
    .padding()
    .background(KhalaGround(style: .menu))
}
