import SFSafeSymbols
import SwiftUI

/// The floating glass bar of a device screen's sections (mockups' `nav`): a 62 pt capsule inset 45 pt from the
/// screen's sides, the active section in the screen's accent on a 12 % tint.
struct KhalaSubTabBar: View {
    let tabs: [KhalaSubTab]
    @Binding var selection: Int
    let category: KhalaCategory

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                let isSelected = index == selection
                Button {
                    selection = index
                } label: {
                    VStack(spacing: 2) {
                        Image(systemSymbol: tab.symbol)
                            .font(.system(size: 18, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(isSelected ? KhalaTheme.accent(category) : KhalaTheme.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background {
                        if isSelected {
                            Capsule().fill(KhalaTheme.accent(category).opacity(0.12))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 62)
        .khalaGlass(in: Capsule())
        .padding(.horizontal, 45)
        .padding(.bottom, 8)
    }
}

#Preview {
    KhalaSubTabBar(
        tabs: [
            KhalaSubTab(title: KhalaScreenText.live, symbol: .videoFill),
            KhalaSubTab(title: KhalaScreenText.events, symbol: .listBullet),
            KhalaSubTab(title: KhalaScreenText.settings, symbol: .gearshape),
        ],
        selection: .constant(0),
        category: .security
    )
    .background(KhalaGround())
}
