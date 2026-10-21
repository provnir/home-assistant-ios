import SFSafeSymbols
import Shared
import SwiftUI
import UIKit

/// The one floating glass bar of a screen's pre-known sections (DESIGN.md: bottom tabs only for those) — Camera,
/// Car, Hot water and the Home Assistant pages whose tabs Khala lifts (Devices & services: Integrations ·
/// Devices · Entities · Helpers). A compact capsule sized to its tabs and centred, at least 24 pt from the
/// screen's sides (`KhalaSubTabMetrics`), floating over content that scrolls on underneath — like the iOS 26
/// floating tab bars, not a full-width footer (Nir, build 19.1).
///
/// The selection lens is ONE view that stays mounted and moves to the chosen tab (its offset animates with
/// `motion`, keyed on `selection`), so it slides on every change — a tap here, or a selection that arrives later
/// from elsewhere (a Home Assistant page reporting its tab). Build 19.1 drew a lens per tab (`if index ==
/// selection`) and relied on `glassEffectID` to morph between them; the lens sat inside the bar's own glass and
/// the morph never showed, so the lens jumped.
///
/// iOS 26: real Liquid Glass. The bar is `.glassEffect(.regular.interactive())` in a `GlassEffectContainer`; the
/// lens is an accent-tinted interactive glass capsule. Touches flex the glass (`interactive()`) and press the tab
/// (`KhalaPressStyle`). Before iOS 26: the regular material, the lens a tinted capsule.
///
/// Why not the system `TabView`: a lifted Home Assistant page has one web view under all its tabs and switches
/// them through the frontend's own tab links, which a `TabView` (one content view per tab) can't host; one bar
/// for every screen keeps the look and the motion identical.
struct KhalaSubTabBar: View {
    let tabs: [KhalaSubTab]
    @Binding var selection: Int
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(tabs: [KhalaSubTab], selection: Binding<Int>, category: KhalaCategory) {
        self.init(tabs: tabs, selection: selection, accent: KhalaTheme.accent(category))
    }

    init(tabs: [KhalaSubTab], selection: Binding<Int>, accent: Color) {
        self.tabs = tabs
        self._selection = selection
        self.accent = accent
    }

    /// The spring the lens and the sections' content move with (a short ease when Reduce Motion is on).
    static func motion(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.78)
    }

    var body: some View {
        GeometryReader { proxy in
            let tabWidth = CGFloat(KhalaSubTabMetrics.tabWidth(available: Double(proxy.size.width), count: tabs.count))
            Group {
                if #available(iOS 26.0, *) {
                    glassBar(tabWidth: tabWidth)
                } else {
                    materialBar(tabWidth: tabWidth)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: CGFloat(KhalaSubTabMetrics.barHeight))
        .padding(.bottom, 8)
        .sensoryFeedbackIfAvailable(selection)
    }

    // MARK: - iOS 26

    @available(iOS 26.0, *)
    private func glassBar(tabWidth: CGFloat) -> some View {
        GlassEffectContainer(spacing: 0) {
            row(tabWidth: tabWidth) {
                Capsule()
                    .fill(Color.clear)
                    .glassEffect(.regular.tint(accent.opacity(0.2)).interactive(), in: Capsule())
            }
            .glassEffect(.regular.interactive(), in: Capsule())
        }
    }

    // MARK: - Before iOS 26

    private func materialBar(tabWidth: CGFloat) -> some View {
        row(tabWidth: tabWidth) {
            Capsule()
                .fill(accent.opacity(0.12))
        }
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5))
        .shadow(color: KhalaTheme.shadow.opacity(0.12), radius: 15, x: 0, y: 12)
    }

    // MARK: - Tabs

    /// The tabs over the one lens, which sits under the selected tab and slides when `selection` changes.
    private func row<Lens: View>(tabWidth: CGFloat, @ViewBuilder lens: () -> Lens) -> some View {
        let offset = KhalaSubTabMetrics.lensOffset(selection: selection, count: tabs.count, tabWidth: Double(tabWidth))
        return ZStack(alignment: .leading) {
            lens()
                .frame(width: tabWidth, height: CGFloat(KhalaSubTabMetrics.lensHeight))
                .offset(x: CGFloat(offset))
                .animation(Self.motion(reduceMotion: reduceMotion), value: selection)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    button(index: index, tab: tab)
                        .frame(width: tabWidth)
                }
            }
            .padding(.horizontal, CGFloat(KhalaSubTabMetrics.inset))
        }
        .frame(
            width: CGFloat(KhalaSubTabMetrics.barWidth(tabWidth: Double(tabWidth), count: tabs.count)),
            height: CGFloat(KhalaSubTabMetrics.barHeight),
            alignment: .leading
        )
        .contentShape(Capsule())
    }

    private func button(index: Int, tab: KhalaSubTab) -> some View {
        let isSelected = index == selection
        return Button {
            guard index != selection else { return }
            // In a transaction too, so a screen's section content (`KhalaDeviceScreen`) transitions with the lens.
            withAnimation(Self.motion(reduceMotion: reduceMotion)) {
                selection = index
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemSymbol: tab.symbol)
                    .font(.system(size: 18, weight: .medium))
                Text(tab.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isSelected ? accent : KhalaTheme.secondary)
            .animation(Self.motion(reduceMotion: reduceMotion), value: isSelected)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: CGFloat(KhalaSubTabMetrics.lensHeight))
            .contentShape(Capsule())
        }
        .buttonStyle(KhalaPressStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A touch-down press: the control dips a little while the finger is on it and springs back.
struct KhalaPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private extension View {
    /// A light selection tick when the section changes (iOS 17+; nothing before).
    @ViewBuilder
    func sensoryFeedbackIfAvailable(_ selection: Int) -> some View {
        if #available(iOS 17.0, *) {
            sensoryFeedback(.selection, trigger: selection)
        } else {
            self
        }
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
