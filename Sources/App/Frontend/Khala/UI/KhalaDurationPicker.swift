import SwiftUI

/// The segmented duration control of the hot-water hero (30 · 45 · 60 · 90 min): a fixed small set, so segmented
/// is fine (DESIGN.md). Flat ground track, the chosen one on a white pill.
struct KhalaDurationPicker: View {
    let durations: [Int]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(durations, id: \.self) { minutes in
                let isSelected = minutes == selection
                Button {
                    selection = minutes
                } label: {
                    Text(KhalaScreenText.minutes(minutes))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? KhalaTheme.ink : KhalaTheme.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if isSelected {
                                Capsule().fill(KhalaTheme.card).khalaCardShadow()
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .frame(height: 44)
        .background(KhalaTheme.groundFlat, in: Capsule())
    }
}

#Preview {
    KhalaDurationPicker(durations: [30, 45, 60, 90], selection: .constant(45)).padding()
}
