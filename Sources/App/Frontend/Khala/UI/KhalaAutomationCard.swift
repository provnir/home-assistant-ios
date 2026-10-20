import SwiftUI

/// An automation that runs a device on a clock (mockup `DayWater` "Tonight"): name, an on/off switch that enables or
/// disables the automation itself, and its description or run length underneath.
struct KhalaAutomationCard: View {
    let automation: KhalaDeviceAutomation
    let category: KhalaCategory
    /// Extra line, e.g. the next run on the Schedule tab.
    var detail: String?
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(automation.name)
                    .font(KhalaTheme.cardTitle)
                    .foregroundStyle(KhalaTheme.ink)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Toggle(automation.name, isOn: Binding(get: { automation.isEnabled }, set: { _ in onToggle() }))
                    .labelsHidden()
                    .tint(KhalaTheme.accent(category))
            }
            if let text = subtitle {
                Text(text)
                    .font(KhalaTheme.secondaryText)
                    .foregroundStyle(KhalaTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KhalaTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .khalaCardShadow()
    }

    private var subtitle: String? {
        let parts = [detail, automation.description, automation.runMinutes.map(KhalaScreenText.runs)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview {
    KhalaAutomationCard(
        automation: KhalaDeviceAutomation(
            automationId: "automation.backup", name: "Smart backup check",
            description: "Heats 07:30–08:15 when the morning looks cloudy.", isEnabled: true,
            fireDates: [], timesOfDay: [0], runMinutes: nil, targetsDevice: false
        ),
        category: .heat,
        onToggle: {}
    )
    .padding()
    .background(KhalaGround())
}
