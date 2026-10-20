import SFSafeSymbols
import SwiftUI

/// The big horizontal volume slider of the media sheet (mockup `DayTheater`): a 56 pt flat track filled in the media
/// accent up to the level, a speaker glyph on the fill. Dragging moves it locally; the level is sent when the drag
/// ends (one `volume_set`, not one per frame). Adjustable for VoiceOver in 5 % steps.
struct KhalaVolumeSlider: View {
    let level: Double
    let onSet: (Double) -> Void

    @State private var dragLevel: Double? = nil

    var body: some View {
        let shown = dragLevel ?? level
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(KhalaTheme.groundFlat)
                Rectangle()
                    .fill(KhalaTheme.accent(.media))
                    .frame(width: max(0, min(width, width * shown)))
                Image(systemSymbol: shown == 0 ? .speakerSlashFill : .speakerWave2Fill)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(shown > 0.08 ? Color.white : KhalaTheme.secondary)
                    .padding(.leading, 18)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragLevel = min(1, max(0, value.location.x / max(width, 1)))
                    }
                    .onEnded { value in
                        let released = min(1, max(0, value.location.x / max(width, 1)))
                        dragLevel = released
                        onSet(released)
                    }
            )
        }
        .frame(height: 56)
        .onChange(of: level) { _ in dragLevel = nil }
        .accessibilityElement()
        .accessibilityLabel(KhalaScreenText.volume.capitalized)
        .accessibilityValue(KhalaMediaLayout.volumeText(shown))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSet(min(1, shown + 0.05))
            case .decrement: onSet(max(0, shown - 0.05))
            @unknown default: break
            }
        }
    }
}

#Preview {
    KhalaVolumeSlider(level: 0.45, onSet: { _ in }).padding()
}
