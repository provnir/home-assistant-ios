import SFSafeSymbols
import SwiftUI

/// A tinted chip of the Now card: category glyph, the device's state in large type, its name below.
struct KhalaDeviceChip: View {
    let device: KhalaDevice
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemSymbol: KhalaTheme.symbol(device.category))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(KhalaTheme.accent(device.category))
                Text(device.stateText)
                    .font(KhalaTheme.chipValue)
                    .foregroundStyle(KhalaTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(device.name)
                    .font(KhalaTheme.chipLabel)
                    .foregroundStyle(KhalaTheme.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(KhalaTheme.tint(device.category), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    KhalaDeviceChip(
        device: KhalaDevice(
            id: "car",
            name: "Rover",
            category: .car,
            primaryEntityId: "sensor.rover_battery_level",
            stateText: "72%",
            memberEntityIds: [],
            isPinned: false
        )
    ) {}
        .frame(width: 110)
        .padding()
}
