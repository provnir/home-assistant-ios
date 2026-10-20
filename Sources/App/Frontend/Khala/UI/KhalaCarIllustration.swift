import SwiftUI

/// The top-down car on the car hero (mockup `DayCar`), drawn in the mockup's 330 × 140 coordinates and scaled to
/// fit: wheels, a light body with a soft vertical sheen, a dark glass roof, mirrors, and two accent arcs — the
/// charge-side light in the car accent (bright while charging or with the port open) and the tail light.
struct KhalaCarIllustration: View {
    /// Charging or charge port open: the charge-side arc lights up.
    let isCharging: Bool

    private static let size = CGSize(width: 330, height: 140)

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / Self.size.width, size.height / Self.size.height)
            context.translateBy(
                x: (size.width - Self.size.width * scale) / 2,
                y: (size.height - Self.size.height * scale) / 2
            )
            context.scaleBy(x: scale, y: scale)

            // Glow under the car.
            let glow = Path(ellipseIn: CGRect(x: 1, y: 8, width: 324, height: 128))
            context.fill(glow, with: .radialGradient(
                Gradient(colors: [KhalaTheme.accent(.car).opacity(0.20), KhalaTheme.accent(.car).opacity(0)]),
                center: CGPoint(x: 163, y: 72),
                startRadius: 0,
                endRadius: 162
            ))

            // Wheels.
            for rect in [
                CGRect(x: 58, y: 16, width: 40, height: 11), CGRect(x: 226, y: 16, width: 40, height: 11),
                CGRect(x: 58, y: 113, width: 40, height: 11), CGRect(x: 226, y: 113, width: 40, height: 11),
            ] {
                context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(Color(white: 0.17)))
            }

            // Body.
            var body = Path()
            body.move(to: CGPoint(x: 44, y: 24))
            body.addCurve(to: CGPoint(x: 276, y: 22), control1: CGPoint(x: 78, y: 15), control2: CGPoint(x: 236, y: 13))
            body.addCurve(to: CGPoint(x: 314, y: 70), control1: CGPoint(x: 300, y: 27), control2: CGPoint(x: 314, y: 46))
            body.addCurve(to: CGPoint(x: 276, y: 118), control1: CGPoint(x: 314, y: 94), control2: CGPoint(x: 300, y: 113))
            body.addCurve(to: CGPoint(x: 44, y: 116), control1: CGPoint(x: 236, y: 127), control2: CGPoint(x: 78, y: 125))
            body.addCurve(to: CGPoint(x: 18, y: 70), control1: CGPoint(x: 28, y: 112), control2: CGPoint(x: 18, y: 94))
            body.addCurve(to: CGPoint(x: 44, y: 24), control1: CGPoint(x: 18, y: 46), control2: CGPoint(x: 28, y: 28))
            body.closeSubpath()
            context.fill(body, with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.973, green: 0.976, blue: 0.984), location: 0),
                    .init(color: Color(red: 0.875, green: 0.890, blue: 0.910), location: 0.5),
                    .init(color: Color(red: 0.933, green: 0.941, blue: 0.953), location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: 14),
                endPoint: CGPoint(x: 0, y: 126)
            ))
            context.stroke(body, with: .color(Color(red: 0.725, green: 0.749, blue: 0.784)), lineWidth: 1)

            // Glass roof.
            var roof = Path()
            roof.move(to: CGPoint(x: 100, y: 33))
            roof.addCurve(to: CGPoint(x: 246, y: 34), control1: CGPoint(x: 140, y: 27), control2: CGPoint(x: 214, y: 27))
            roof.addCurve(to: CGPoint(x: 246, y: 106), control1: CGPoint(x: 258, y: 46), control2: CGPoint(x: 258, y: 94))
            roof.addCurve(to: CGPoint(x: 100, y: 107), control1: CGPoint(x: 214, y: 113), control2: CGPoint(x: 140, y: 113))
            roof.addCurve(to: CGPoint(x: 100, y: 33), control1: CGPoint(x: 91, y: 92), control2: CGPoint(x: 91, y: 48))
            roof.closeSubpath()
            context.fill(roof, with: .linearGradient(
                Gradient(colors: [Color(red: 0.157, green: 0.192, blue: 0.239), Color(red: 0.290, green: 0.337, blue: 0.392)]),
                startPoint: CGPoint(x: 100, y: 27),
                endPoint: CGPoint(x: 258, y: 113)
            ))
            var sheen = Path()
            sheen.move(to: CGPoint(x: 110, y: 40))
            sheen.addCurve(to: CGPoint(x: 232, y: 41), control1: CGPoint(x: 150, y: 36), control2: CGPoint(x: 200, y: 36))
            context.stroke(sheen, with: .color(.white.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

            // Hood line.
            var hood = Path()
            hood.move(to: CGPoint(x: 246, y: 34))
            hood.addCurve(to: CGPoint(x: 270, y: 70), control1: CGPoint(x: 262, y: 44), control2: CGPoint(x: 270, y: 58))
            hood.addCurve(to: CGPoint(x: 246, y: 106), control1: CGPoint(x: 270, y: 82), control2: CGPoint(x: 262, y: 96))
            context.stroke(hood, with: .color(Color(red: 0.788, green: 0.808, blue: 0.835)), lineWidth: 1)

            // Mirrors.
            for center in [CGPoint(x: 224, y: 17), CGPoint(x: 224, y: 123)] {
                let mirror = Path(ellipseIn: CGRect(x: center.x - 8, y: center.y - 3.2, width: 16, height: 6.4))
                context.fill(mirror, with: .color(Color(red: 0.890, green: 0.902, blue: 0.918)))
                context.stroke(mirror, with: .color(Color(red: 0.725, green: 0.749, blue: 0.784)), lineWidth: 0.8)
            }

            // Lights: front (charge side) and tail.
            var front = Path()
            front.move(to: CGPoint(x: 306, y: 50))
            front.addCurve(to: CGPoint(x: 306, y: 90), control1: CGPoint(x: 311, y: 58), control2: CGPoint(x: 311, y: 82))
            context.stroke(front, with: .color(KhalaTheme.accent(.car).opacity(isCharging ? 1 : 0.55)),
                           style: StrokeStyle(lineWidth: isCharging ? 2.6 : 1.8, lineCap: .round))
            var tail = Path()
            tail.move(to: CGPoint(x: 24, y: 52))
            tail.addCurve(to: CGPoint(x: 24, y: 88), control1: CGPoint(x: 21, y: 60), control2: CGPoint(x: 21, y: 80))
            context.stroke(tail, with: .color(Color(red: 0.847, green: 0.278, blue: 0.231).opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
        .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    KhalaCarIllustration(isCharging: true)
        .frame(width: 322, height: 136)
        .padding()
}
