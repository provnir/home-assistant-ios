import SFSafeSymbols
import Shared
import SwiftUI

/// A 44 pt round button of floating chrome (menu, search, back). Liquid Glass on iOS 26, the regular material with
/// a hairline and a soft drop shadow before that — the only place Khala uses glass (DESIGN.md "Principles").
struct KhalaGlassButton: View {
    let symbol: SFSymbol
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemSymbol: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(KhalaTheme.ink)
                .frame(width: 44, height: 44)
                .modify { view in
                    // Same guard and fallback as `HomeAssistantStandByView`'s round glass buttons.
                    if #available(iOS 26.0, *) {
                        view.glassEffect(.regular.interactive(), in: .circle)
                    } else {
                        view
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5))
                            .shadow(color: KhalaTheme.shadow.opacity(0.10), radius: 9, x: 0, y: 6)
                    }
                }
                .contentShape(Circle())
        }
        // iOS 26's interactive glass answers the touch itself; the press style adds the same dip before it.
        .buttonStyle(KhalaPressStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    ZStack {
        KhalaGround()
        HStack {
            KhalaGlassButton(symbol: .sidebarLeft, accessibilityLabel: KhalaText.openMenu) {}
            Spacer()
            KhalaGlassButton(symbol: .magnifyingglass, accessibilityLabel: KhalaText.search) {}
        }
        .padding(16)
    }
}
