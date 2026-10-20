import SwiftUI

/// A timeline dot: filled for what happened, outlined for what's coming, a larger ink dot with a halo for Now.
struct KhalaTimelineDot: View {
    enum Style: Equatable {
        case past(KhalaCategory)
        case upcoming(KhalaCategory)
        case now
    }

    let style: Style

    static let size: CGFloat = 9
    static let nowSize: CGFloat = 15

    var body: some View {
        switch style {
        case let .past(category):
            Circle()
                .fill(KhalaTheme.accent(category))
                .frame(width: Self.size, height: Self.size)
        case let .upcoming(category):
            Circle()
                .fill(KhalaTheme.groundFlat)
                .overlay(Circle().strokeBorder(KhalaTheme.accent(category), lineWidth: 1.5))
                .frame(width: Self.size, height: Self.size)
        case .now:
            Circle()
                .fill(KhalaTheme.ink)
                .frame(width: Self.nowSize, height: Self.nowSize)
                .background(
                    Circle()
                        .fill(KhalaTheme.ink.opacity(0.10))
                        .frame(width: Self.nowSize + 10, height: Self.nowSize + 10)
                )
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        KhalaTimelineDot(style: .past(.security))
        KhalaTimelineDot(style: .now)
        KhalaTimelineDot(style: .upcoming(.heat))
    }
    .padding()
    .background(KhalaGround())
}
