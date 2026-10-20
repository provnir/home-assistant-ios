import SwiftUI

/// The calm ground behind Khala's screens: a soft top-to-bottom wash with a faint warm glow at the top right and a
/// faint cool glow at the bottom left (DESIGN.md "ground"). The menu panel uses a slightly darker variant so the
/// card above it reads as lifted.
struct KhalaGround: View {
    enum Style {
        case screen
        case menu
    }

    var style: Style = .screen
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let glowScale = colorScheme == .dark ? 0.5 : 1
        ZStack {
            switch style {
            case .screen:
                LinearGradient(
                    stops: [
                        .init(color: KhalaTheme.groundTop, location: 0),
                        .init(color: KhalaTheme.groundFlat, location: 0.48),
                        .init(color: KhalaTheme.groundBottom, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [KhalaTheme.warmGlow.opacity(0.16 * glowScale), KhalaTheme.warmGlow.opacity(0)],
                    center: UnitPoint(x: 0.85, y: -0.05),
                    startRadius: 0,
                    endRadius: 360
                )
                RadialGradient(
                    colors: [KhalaTheme.coolGlow.opacity(0.10 * glowScale), KhalaTheme.coolGlow.opacity(0)],
                    center: UnitPoint(x: -0.15, y: 1.07),
                    startRadius: 0,
                    endRadius: 420
                )
            case .menu:
                LinearGradient(
                    stops: [
                        .init(color: KhalaTheme.menuTop, location: 0),
                        .init(color: KhalaTheme.menuMiddle, location: 0.5),
                        .init(color: KhalaTheme.menuBottom, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [KhalaTheme.warmGlow.opacity(0.14 * glowScale), KhalaTheme.warmGlow.opacity(0)],
                    center: UnitPoint(x: 0, y: -0.05),
                    startRadius: 0,
                    endRadius: 320
                )
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    HStack(spacing: 0) {
        KhalaGround(style: .menu)
        KhalaGround()
    }
}
