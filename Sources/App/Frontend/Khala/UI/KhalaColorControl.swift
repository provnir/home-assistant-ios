import SwiftUI
import UIKit

/// A light's colour as the system colour picker (DESCRIPTORS-DESIGN.md §3, "Colour ●"): the swatch shows the
/// light's hue and saturation; a pick is sent 300 ms after the picker stops moving, as one `light.turn_on`.
struct KhalaColorControl: View {
    let control: KhalaControlModel
    let category: KhalaAccent
    let onIntent: (KhalaIntent) -> Void

    @State private var send: Task<Void, Never>?

    var body: some View {
        let (hue, saturation): (Double?, Double?) = {
            if case let .color(hue, saturation) = control.kind { return (hue, saturation) }
            return (nil, nil)
        }()
        let current = Color(hue: (hue ?? 0) / 360, saturation: (saturation ?? 0) / 100, brightness: 1)
        ColorPicker(
            selection: Binding(
                get: { current },
                set: { picked in schedule(picked) }
            ),
            supportsOpacity: false
        ) {
            Text(control.title)
                .font(KhalaTheme.rowTitle)
                .foregroundStyle(KhalaTheme.ink)
        }
        .disabled(!control.isEnabled)
        .onDisappear { send?.cancel() }
    }

    private func schedule(_ color: Color) {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return
        }
        send?.cancel()
        send = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            onIntent(.setColor(hue: Double(hue) * 360, saturation: Double(saturation) * 100))
        }
    }
}

#Preview {
    KhalaColorControl(
        control: KhalaControlModel(entityId: "light.shelf", title: "Colour", symbol: .sf("paintpalette.fill"),
                                   kind: .color(hue: 30, saturation: 80), confirm: nil),
        category: .sun,
        onIntent: { _ in }
    )
    .padding()
}
