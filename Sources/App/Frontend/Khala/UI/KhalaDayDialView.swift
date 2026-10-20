import SwiftUI

/// The 24-hour dial on the hot-water hero (mockup `DayWater`): a ring with hour ticks, today's sun band, the windows
/// automations heat in (with the first one's start time), a now marker, and the heater's state in the middle.
/// Geometry comes from `KhalaDayDial`.
struct KhalaDayDialView<Center: View>: View {
    let dial: KhalaDayDial
    let isOn: Bool
    @ViewBuilder let center: () -> Center

    private static var sunBand: Color { Color(red: 241 / 255, green: 215 / 255, blue: 154 / 255) }
    private static var ring: Color { KhalaTheme.groundFlat }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            // The mockup's 260-unit dial: ring radius 104, stroke 13.
            let unit = side / 260
            let radius = 104 * unit
            let lineWidth = 13 * unit
            let middle = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                Circle()
                    .stroke(Self.ring, lineWidth: lineWidth)
                    .frame(width: radius * 2, height: radius * 2)
                if let sun = dial.sun {
                    arc(sun, radius: radius)
                        .stroke(Self.sunBand, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
                ForEach(Array(dial.windows.enumerated()), id: \.offset) { _, window in
                    arc(window, radius: radius, minimumSweep: 4)
                        .stroke(KhalaTheme.accent(.heat), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
                ticks(radius: radius, unit: unit, middle: middle)
                    .stroke(KhalaTheme.line, style: StrokeStyle(lineWidth: 1.4 * unit, lineCap: .round))
                hourLabels(radius: radius, unit: unit)
                if let first = dial.windows.first {
                    let point = KhalaDayDial.point(angle: KhalaDayDial.angle(secondsOfDay: first.start), radius: Double(radius - 34 * unit))
                    Text(KhalaDayDial.text(.init(start: first.start, end: first.start)))
                        .font(.system(size: 11 * max(unit, 0.85), weight: .bold))
                        .foregroundStyle(KhalaTheme.accent(.heat))
                        .position(x: middle.x + CGFloat(point.x), y: middle.y + CGFloat(point.y))
                }
                nowMarker(radius: radius, unit: unit)
                center()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let sun = dial.sun { parts.append("Sun \(KhalaDayDial.text(sun))") }
        for window in dial.windows { parts.append("heating window \(KhalaDayDial.text(window))") }
        parts.append("now \(KhalaDayDial.text(.init(start: dial.now, end: dial.now)))")
        parts.append(isOn ? KhalaScreenText.on : KhalaScreenText.off)
        return parts.joined(separator: ", ")
    }

    /// A clockwise arc for a band, in a square frame centred on the dial.
    private func arc(_ band: KhalaDayDial.Band, radius: CGFloat, minimumSweep: Double = 0) -> some Shape {
        KhalaDialArc(
            startAngle: KhalaDayDial.angle(secondsOfDay: band.start),
            sweep: max(KhalaDayDial.sweep(band), minimumSweep),
            radius: radius
        )
    }

    private func ticks(radius: CGFloat, unit: CGFloat, middle: CGPoint) -> Path {
        Path { path in
            for hour in 0 ..< 24 {
                let angle = KhalaDayDial.angle(secondsOfDay: hour * 3600)
                let inner = KhalaDayDial.point(angle: angle, radius: Double(radius - 12 * unit))
                let outer = KhalaDayDial.point(angle: angle, radius: Double(radius - 8 * unit))
                path.move(to: CGPoint(x: inner.x, y: inner.y))
                path.addLine(to: CGPoint(x: outer.x, y: outer.y))
            }
        }
        .offsetBy(dx: middle.x, dy: middle.y)
    }

    private func hourLabels(radius: CGFloat, unit: CGFloat) -> some View {
        GeometryReader { proxy in
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                let point = KhalaDayDial.point(
                    angle: KhalaDayDial.angle(secondsOfDay: hour * 3600),
                    radius: Double(radius + 22 * unit)
                )
                Text(String(format: "%02d", hour))
                    .font(.system(size: 12 * max(unit, 0.85), weight: .semibold))
                    .foregroundStyle(KhalaTheme.muted)
                    .position(x: proxy.size.width / 2 + CGFloat(point.x), y: proxy.size.height / 2 + CGFloat(point.y))
            }
        }
    }

    private func nowMarker(radius: CGFloat, unit: CGFloat) -> some View {
        GeometryReader { proxy in
            let angle = KhalaDayDial.angle(secondsOfDay: dial.now)
            let outer = KhalaDayDial.point(angle: angle, radius: Double(radius + 13 * unit))
            let inner = KhalaDayDial.point(angle: angle, radius: Double(radius - 14 * unit))
            let dot = KhalaDayDial.point(angle: angle, radius: Double(radius))
            let middle = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            Path { path in
                path.move(to: CGPoint(x: middle.x + CGFloat(outer.x), y: middle.y + CGFloat(outer.y)))
                path.addLine(to: CGPoint(x: middle.x + CGFloat(inner.x), y: middle.y + CGFloat(inner.y)))
            }
            .stroke(KhalaTheme.ink, style: StrokeStyle(lineWidth: 2 * unit, lineCap: .round))
            Circle()
                .fill(KhalaTheme.ink)
                .overlay(Circle().stroke(KhalaTheme.card, lineWidth: 2 * unit))
                .frame(width: 11 * unit, height: 11 * unit)
                .position(x: middle.x + CGFloat(dot.x), y: middle.y + CGFloat(dot.y))
        }
    }
}

#Preview {
    KhalaDayDialView(
        dial: KhalaDayDial(sun: .init(start: 24480, end: 64920), windows: [.init(start: 27000, end: 29700)], now: 45000),
        isOn: false
    ) {
        Text("Off").font(.system(size: 44, weight: .semibold))
    }
    .frame(width: 220, height: 220)
    .padding()
}
