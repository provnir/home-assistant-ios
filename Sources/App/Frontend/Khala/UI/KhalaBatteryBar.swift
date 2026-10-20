import SwiftUI

/// The car's battery bar (mockup `DayCar`): a 10 pt track in the car tint, the charge in the accent, and an ink
/// tick at the charge limit with its label underneath.
struct KhalaBatteryBar: View {
    /// 0...100.
    let level: Double
    /// 0...100, nil when the car has no charge limit.
    let limit: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(KhalaTheme.tint(.car))
                    .frame(height: 10)
                Capsule()
                    .fill(KhalaTheme.accent(.car))
                    .frame(width: max(10, width * min(1, max(0, level / 100))), height: 10)
                if let limit {
                    let x = width * min(1, max(0, limit / 100))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(KhalaTheme.ink)
                        .frame(width: 2, height: 18)
                        .offset(x: x - 1, y: -4)
                    Text(KhalaScreenText.limit("\(Int(limit.rounded()))%"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(KhalaTheme.secondary)
                        .fixedSize()
                        .position(x: min(max(x, 34), width - 34), y: 23)
                }
            }
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("Battery \(Int(level.rounded())) percent" + (limit.map { ", limit \(Int($0)) percent" } ?? ""))
    }
}

#Preview {
    KhalaBatteryBar(level: 72, limit: 80).padding()
}
