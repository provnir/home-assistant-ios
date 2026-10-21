import SFSafeSymbols
import Shared
import SwiftUI
import UIKit

/// The one floating glass bar of a screen's pre-known sections (DESIGN.md: bottom tabs only for those) — Camera,
/// Car, Hot water and the Home Assistant pages whose tabs Khala lifts (Devices & services: Integrations ·
/// Devices · Entities · Helpers). A 62 pt capsule inset 45 pt from the screen's sides.
///
/// iOS 26: real Liquid Glass. The bar and the selection "lens" share one `GlassEffectContainer`; the bar is
/// `.glassEffect(.regular.interactive())`, the lens is an accent-tinted interactive glass capsule whose
/// `glassEffectID` moves to the chosen tab inside a spring animation, so the glass itself morphs across rather
/// than a fill sliding. Touches flex the glass (`interactive()`) and press the tab (`KhalaPressStyle`).
/// Before iOS 26: the regular material, with the lens a tinted capsule carried across by `matchedGeometryEffect`.
///
/// Why not the system `TabView`: a lifted Home Assistant page has one web view under all its tabs and switches
/// them through the frontend's own tab links, which a `TabView` (one content view per tab) can't host; one bar
/// for every screen keeps the look and the motion identical.
struct KhalaSubTabBar: View {
    let tabs: [KhalaSubTab]
    @Binding var selection: Int
    let accent: Color

    @Namespace private var lens
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
        Group {
            if #available(iOS 26.0, *) {
                glassBar
            } else {
                materialBar
            }
        }
        .padding(.horizontal, 45)
        .padding(.bottom, 8)
        .sensoryFeedbackIfAvailable(selection)
    }

    // MARK: - iOS 26

    @available(iOS 26.0, *)
    private var glassBar: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    button(index: index, tab: tab) {
                        if index == selection {
                            Capsule()
                                .fill(Color.clear)
                                .glassEffect(.regular.tint(accent.opacity(0.2)).interactive(), in: Capsule())
                                .glassEffectID("lens", in: lens)
                        }
                    }
                }
            }
            .padding(.horizontal, 5)
            .frame(height: 62)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
    }

    // MARK: - Before iOS 26

    private var materialBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                button(index: index, tab: tab) {
                    if index == selection {
                        Capsule()
                            .fill(accent.opacity(0.12))
                            .matchedGeometryEffect(id: "lens", in: lens)
                    }
                }
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 62)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5))
        .shadow(color: KhalaTheme.shadow.opacity(0.12), radius: 15, x: 0, y: 12)
    }

    // MARK: - Tabs

    private func button<Lens: View>(index: Int, tab: KhalaSubTab, @ViewBuilder lens: () -> Lens) -> some View {
        let isSelected = index == selection
        return Button {
            guard index != selection else { return }
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
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? accent : KhalaTheme.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background { lens() }
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
