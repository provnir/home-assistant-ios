import Shared
import SwiftUI

extension View {
    /// Floating chrome's glass (DESIGN.md: Liquid Glass only on floating chrome): Liquid Glass on iOS 26, the
    /// regular material with a hairline and a soft shadow before — the same guard and fallback as
    /// `KhalaGlassButton`.
    func khalaGlass<S: Shape>(in shape: S) -> some View {
        modify { view in
            if #available(iOS 26.0, *) {
                view.glassEffect(.regular, in: shape)
            } else {
                view
                    .background(.regularMaterial, in: shape)
                    .overlay(shape.stroke(Color.white.opacity(0.9), lineWidth: 0.5))
                    .shadow(color: KhalaTheme.shadow.opacity(0.10), radius: 9, x: 0, y: 6)
            }
        }
    }
}
