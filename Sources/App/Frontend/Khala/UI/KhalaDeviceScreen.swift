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
    /// Pull to refresh, for screens whose data can be asked for again (the car's).
    var onRefresh: (() async -> Void)?

    /// The section shown before the current one: the new section slides in from its side.
    @State private var lastSelection = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    // Sections cross-fade and slide in from the side of the tab chosen, with the bar's lens
                    // (`KhalaSubTabBar.motion`); the old and the new section overlap while they do, so the new one
                    // doesn't start below the old.
                    // The section is ONE view, a VStack: a section is several sibling views (hero card, grid,
                    // "Recent", ...), and put straight into the ZStack each sibling became its own ZStack layer —
                    // every screen's views piled up at the top-left (build 24.1: the car's grid over its hero, the
                    // camera's timeline over the live card). Only the section as a whole is stacked and animated.
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 0) {
                            content()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(selection)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(x: selection >= lastSelection ? 28 : -28)),
                                removal: .opacity
                            ))
                    }
                    .animation(KhalaSubTabBar.motion(reduceMotion: reduceMotion), value: selection)
                    .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, KhalaTheme.gutter)
                .padding(.top, 9 + 44 + 4)
                .padding(.bottom, tabs.isEmpty ? 32 : 62 + 8 + 32)
            }
            .scrollIndicators(.hidden)
            .modifier(KhalaRefreshable(action: onRefresh))

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
        .onAppear { lastSelection = selection }
        // After the frame that changed it, so that frame still slides in from the old section's side.
        .onChange(of: selection) { lastSelection = $0 }
    }
}

/// Pull to refresh when the screen has something to refresh; nothing (no spinner) otherwise.
private struct KhalaRefreshable: ViewModifier {
    let action: (() async -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let action {
            content.refreshable { await action() }
        } else {
            content
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
