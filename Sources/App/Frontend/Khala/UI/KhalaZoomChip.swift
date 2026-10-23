import SFSafeSymbols
import SwiftUI

/// "2.5×" over a zoomed picture (the live player, the still viewer); a tap zooms back to 1×.
struct KhalaZoomChip: View {
    /// `KhalaLiveZoom.label(_:)`.
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemSymbol: .plusMagnifyingglass)
                Text(label).monospacedDigit()
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(.black.opacity(0.55), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zoom \(label), reset")
    }
}

#Preview {
    ZStack {
        Color.gray
        KhalaZoomChip(label: "2.5×") {}
    }
}
