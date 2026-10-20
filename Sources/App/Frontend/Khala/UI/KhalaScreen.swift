import SFSafeSymbols
import SwiftUI

/// The frame of a secondary Khala screen: the floating menu button, a large title with a subtitle,
/// and the screen's content in a vertical scroll view. The ground itself is drawn by the shell.
struct KhalaScreen<Content: View>: View {
    let title: String
    let subtitle: String?
    let onMenu: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(KhalaTheme.largeTitle)
                        .kerning(0.3)
                        .foregroundStyle(KhalaTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(KhalaTheme.headerSubtitle)
                            .foregroundStyle(KhalaTheme.secondary)
                            .padding(.top, 1)
                    }
                    content()
                        .padding(.top, 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, KhalaTheme.gutter)
                .padding(.top, 9 + 44 + 4)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)

            HStack {
                KhalaGlassButton(symbol: .sidebarLeft, accessibilityLabel: KhalaText.openMenu, action: onMenu)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 9)
        }
    }
}

#Preview {
    KhalaScreen(title: KhalaText.cameras, subtitle: "8 cameras", onMenu: {}) {
        Text("Content")
    }
    .background(KhalaGround())
}
