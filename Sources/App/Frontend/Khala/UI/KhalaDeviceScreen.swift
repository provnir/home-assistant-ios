import SFSafeSymbols
import SwiftUI

/// The frame of a device or camera screen (mockups `DayCamera`, `DayCar`, `DayWater`). Its only leading control is
/// the shell's pinned menu button (`KhalaShellView.menuButtonInset`): no back button beside it, the drawer is the
/// navigation (Nir, build 14.1). Then an optional trailing control, the large title (a view, so the camera's can be
/// a pull-down), a subtitle, the content in a vertical scroll view, and the sections' glass bar floating at the
/// bottom. The ground is the shell's.
struct KhalaDeviceScreen<Title: View, Trailing: View, Content: View>: View {
    let subtitle: String?
    let tabs: [KhalaSubTab]
    @Binding var selection: Int
    let category: KhalaCategory
    @ViewBuilder let title: () -> Title
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    title()
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(KhalaTheme.headerSubtitle)
                            .foregroundStyle(KhalaTheme.secondary)
                            .lineLimit(2)
                            .padding(.top, 1)
                    }
                    // Sections cross-fade (and settle a few points) as the bar's lens moves; the bar animates
                    // the change (`KhalaSubTabBar.motion`).
                    content()
                        .id(selection)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 10)),
                            removal: .opacity
                        ))
                        .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, KhalaTheme.gutter)
                .padding(.top, 9 + 44 + 4)
                .padding(.bottom, tabs.isEmpty ? 32 : 62 + 8 + 32)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 8) {
                // The shell's menu button occupies the first 44 pt slot, the only leading control.
                Color.clear.frame(width: 44, height: 44)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 16)
            .padding(.top, 9)

            if tabs.count > 1 {
                KhalaSubTabBar(tabs: tabs, selection: $selection, category: category)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

#Preview {
    KhalaDeviceScreen(
        subtitle: "Model · at home",
        tabs: [
            KhalaSubTab(title: KhalaScreenText.overview, symbol: .car),
            KhalaSubTab(title: KhalaScreenText.climate, symbol: .fanblades),
            KhalaSubTab(title: KhalaScreenText.charging, symbol: .boltFill),
        ],
        selection: .constant(0),
        category: .car,
        title: { KhalaLargeTitle(text: "Rover") },
        trailing: { EmptyView() },
        content: { Text("Content") }
    )
    .background(KhalaGround())
}
