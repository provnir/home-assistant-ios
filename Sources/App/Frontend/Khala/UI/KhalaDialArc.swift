import SwiftUI

/// An arc of the dial: from `startAngle` (degrees clockwise from 12 o'clock) clockwise by `sweep` degrees, on a
/// circle of `radius` centred in the shape's rect.
struct KhalaDialArc: Shape {
    let startAngle: Double
    let sweep: Double
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // SwiftUI angles run clockwise from 3 o'clock on screen; the dial's from 12 o'clock.
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .degrees(startAngle - 90),
            endAngle: .degrees(startAngle - 90 + sweep),
            clockwise: false
        )
        return path
    }
}

#Preview {
    KhalaDialArc(startAngle: 270, sweep: 180, radius: 80)
        .stroke(.orange, lineWidth: 12)
        .frame(width: 200, height: 200)
}
