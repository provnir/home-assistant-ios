import SFSafeSymbols
import SwiftUI

/// The big horizontal slider of the light and fan panels (brightness, warmth, speed): a 48 pt flat track filled in
/// the screen's accent up to the level, the control's glyph on the fill, as the media sheet's volume slider. The
/// fill follows the finger, snapped to the slider's own grid (a four-speed fan stops at its four speeds), and one
/// value is sent when the drag ends, never one per frame. Adjustable for VoiceOver one grid step (or 5 %) at a time.
struct KhalaLevelSlider: View {
    let slider: KhalaSlider
    /// The value shown (pending included), in the slider's own unit; nil reads as the bottom of its range.
    let value: Double?
    let symbol: KhalaGlyph
    let category: KhalaAccent
    let title: String
    var isEnabled = true
    let onSet: (Double) -> Void

    @State private var dragValue: Double?

    var body: some View {
        let shown = dragValue ?? value ?? slider.range.lowerBound
        let fraction = slider.fraction(shown)
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(KhalaTheme.groundFlat)
                Rectangle()
                    .fill(KhalaTheme.accent(category))
                    .frame(width: max(0, min(width, width * fraction)))
                KhalaTheme.image(symbol)
                    .font(KhalaTheme.sliderGlyph)
                    .foregroundStyle(fraction > 0.1 ? Color.white : KhalaTheme.secondary)
                    .padding(.leading, 16)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragValue = slider.value(atFraction: drag.location.x / max(width, 1))
                    }
                    .onEnded { drag in
                        let released = slider.value(atFraction: drag.location.x / max(width, 1))
                        dragValue = released
                        onSet(released)
                    }
            )
            .allowsHitTesting(isEnabled)
        }
        .frame(height: 48)
        // A drag on the track is the slider's, never the menu drawer's.
        .khalaClaimsHorizontalDrags()
        .opacity(isEnabled ? 1 : 0.45)
        .onChange(of: value) { _ in dragValue = nil }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(slider.text(shown))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let step = accessibilityStep
            switch direction {
            case .increment: onSet(slider.snapped(shown + step))
            case .decrement: onSet(slider.snapped(shown - step))
            @unknown default: break
            }
        }
    }

    /// One fan speed, else 5 % of the range.
    private var accessibilityStep: Double {
        if case let .percentage(step) = slider, step > 1 { return step }
        return (slider.range.upperBound - slider.range.lowerBound) * 0.05
    }
}

#Preview {
    VStack(spacing: 16) {
        KhalaLevelSlider(slider: .brightness, value: 70, symbol: .sf("sun.max.fill"), category: .sun,
                         title: "Brightness", onSet: { _ in })
        KhalaLevelSlider(slider: .percentage(step: 25), value: 50, symbol: .sf("fanblades.fill"), category: .neutral,
                         title: "Speed", onSet: { _ in })
    }
    .padding()
}
