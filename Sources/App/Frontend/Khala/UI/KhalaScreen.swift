import SwiftUI

/// The frame of a secondary Khala screen: a large title with a subtitle and the screen's content in a vertical
/// scroll view. The ground and the menu button are the shell's (`KhalaShellView` pins the button top-leading in
/// the safe area over every native screen); the scroll view runs on under the status bar and home indicator.
struct KhalaScreen<Content: View>: View {
    let title: String
    let subtitle: String?
    /// Kept for call-site compatibility; the shell owns the menu button now.
    let onMenu: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
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
            // Room for the shell's menu button above the title.
            .padding(.top, 9 + 44 + 4)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }
}

#Preview {
    KhalaScreen(title: KhalaText.cameras, subtitle: "8 cameras", onMenu: {}) {
        Text("Content")
    }
    .background(KhalaGround())
}
