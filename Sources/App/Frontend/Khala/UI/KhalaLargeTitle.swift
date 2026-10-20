import SwiftUI

/// The large title of a device screen, as `KhalaScreen` draws it.
struct KhalaLargeTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(KhalaTheme.largeTitle)
            .kerning(0.3)
            .foregroundStyle(KhalaTheme.ink)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }
}

#Preview {
    KhalaLargeTitle(text: "Hot water")
}
