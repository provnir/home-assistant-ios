import SFSafeSymbols
import SwiftUI

/// A past event on the timeline (a camera detection): thumbnail with a category badge, title and subtitle on a
/// solid white card. The thumbnail is the capture saved for the detection (`KhalaCaptureThumbnail`, from the
/// shell's `KhalaCaptureSource`), the tinted placeholder when there is none.
struct KhalaEventCard: View {
    let title: String
    let subtitle: String?
    let category: KhalaCategory
    /// The detection whose capture is the thumbnail.
    var capture: KhalaCaptureRef?
    let action: () -> Void

    static let height: CGFloat = 72

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                KhalaCaptureThumbnail(ref: capture, category: category)
                    .frame(width: 64, height: 48)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(KhalaTheme.accent(category))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Image(systemSymbol: .personFill)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.white)
                            )
                            .padding(4)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(KhalaTheme.cardTitle)
                        .foregroundStyle(KhalaTheme.ink)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(KhalaTheme.secondaryText)
                            .foregroundStyle(KhalaTheme.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .frame(height: Self.height)
            .background(KhalaTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .khalaCardShadow()
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    KhalaEventCard(title: "Person at Porch", subtitle: "Field detection", category: .security) {}
        .padding()
        .background(KhalaGround())
}
