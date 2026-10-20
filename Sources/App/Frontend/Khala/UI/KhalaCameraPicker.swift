import SFSafeSymbols
import SwiftUI

/// The camera title's pull-down (mockup `DayCameraPicker`): "All cameras", then every camera in a vertical list with
/// its state on the right ("Person 07:35" in the accent, "Clear" muted), the current one checked. Never
/// side-scrolls; a long list scrolls vertically inside the panel.
struct KhalaCameraPicker: View {
    let rows: [KhalaCameraRow]
    let selectedId: String
    let onAllCameras: () -> Void
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            KhalaTheme.groundFlat.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityLabel(KhalaScreenText.close)
                .accessibilityAddTraits(.isButton)

            VStack(spacing: 0) {
                item(title: KhalaScreenText.allCameras, symbol: .squareGrid2x2, trailing: nil, isSelected: false,
                     action: onAllCameras)
                Rectangle()
                    .fill(KhalaTheme.line)
                    .frame(height: 0.5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            item(
                                title: row.name,
                                symbol: row.entityId == selectedId ? .checkmark : nil,
                                trailing: row,
                                isSelected: row.entityId == selectedId
                            ) {
                                onSelect(row.entityId)
                            }
                        }
                    }
                }
                // Up to nine rows show; more scroll vertically inside the panel.
                .frame(height: CGFloat(min(rows.count, 9)) * 44)
            }
            .padding(6)
            .frame(width: 276)
            .khalaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.leading, 16)
            .padding(.top, 9 + 44 + 4 + 44 + 4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(KhalaScreenText.chooseCamera)
        }
    }

    private func item(
        title: String,
        symbol: SFSymbol?,
        trailing: KhalaCameraRow?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if let symbol {
                        Image(systemSymbol: symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? KhalaTheme.accent(.security) : KhalaTheme.ink)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 16)
                Text(title)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(KhalaTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing.stateText)
                        .font(.system(size: 13, weight: trailing.hasDetectionToday ? .semibold : .regular))
                        .foregroundStyle(trailing.hasDetectionToday ? KhalaTheme.accent(.security) : KhalaTheme.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(KhalaTheme.accent(.security).opacity(0.10))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    KhalaCameraPicker(
        rows: [
            KhalaCameraRow(entityId: "camera.a", name: "Front", stateText: "Person 07:35", hasDetectionToday: true,
                           isUnavailable: false),
            KhalaCameraRow(entityId: "camera.b", name: "Back", stateText: "Clear", hasDetectionToday: false,
                           isUnavailable: false),
        ],
        selectedId: "camera.a",
        onAllCameras: {},
        onSelect: { _ in },
        onDismiss: {}
    )
    .background(KhalaGround())
}
