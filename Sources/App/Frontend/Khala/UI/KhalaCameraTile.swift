import SwiftUI
import UIKit

/// A camera in the Cameras grid: a still from the camera (cached with the camera player's picker stills), its name
/// and its state ("Person 07:35" / "Clear").
struct KhalaCameraTile: View {
    let row: KhalaCameraRow
    let actions: KhalaScreenActions
    let action: () -> Void

    @State private var image: UIImage? = nil

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    KhalaTheme.thumbnail
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemSymbol: .videoFill)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                }
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name)
                        .font(KhalaTheme.cardTitle)
                        .foregroundStyle(KhalaTheme.ink)
                        .lineLimit(1)
                    Text(row.stateText)
                        .font(.system(size: 13, weight: row.hasDetectionToday ? .semibold : .regular))
                        .foregroundStyle(row.hasDetectionToday ? KhalaTheme.accent(.security) : KhalaTheme.tertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
            .padding(6)
            .background(KhalaTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .khalaCardShadow()
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .task(id: row.entityId) {
            image = await actions.thumbnail(cameraEntityId: row.entityId)
        }
    }
}
