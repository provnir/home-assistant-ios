import SwiftUI

/// The card at "Now": one line of conditions and up to three tinted device chips.
struct KhalaNowCard: View {
    let headline: String
    let chips: [KhalaDevice]
    let onDevice: (KhalaDevice) -> Void

    var body: some View {
        let shown = Array(chips.prefix(3))
        VStack(alignment: .leading, spacing: 12) {
            Text(headline)
                .font(KhalaTheme.cardTitle)
                .foregroundStyle(KhalaTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !shown.isEmpty {
                HStack(spacing: 8) {
                    ForEach(shown) { device in
                        KhalaDeviceChip(device: device) { onDevice(device) }
                    }
                    // Keep three equal columns when fewer devices are known.
                    ForEach(shown.count ..< 3, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KhalaTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .khalaCardShadow(lifted: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(KhalaText.rightNow)
    }
}

#Preview {
    KhalaNowCard(
        headline: "21° and sunny · sunset in 5 h 32 m",
        chips: [
            KhalaDevice(
                id: "a", name: "Rover", category: .car, primaryEntityId: "sensor.a",
                stateText: "72%", memberEntityIds: [], isPinned: false
            ),
            KhalaDevice(
                id: "b", name: "Hot water", category: .heat, primaryEntityId: "switch.b",
                stateText: "Off", memberEntityIds: [], isPinned: true
            ),
        ],
        onDevice: { _ in }
    )
    .padding()
    .background(KhalaGround())
}
