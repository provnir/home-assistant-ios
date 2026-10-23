import SFSafeSymbols
import SwiftUI
import UIKit

/// The full-screen still viewer, one for every still Khala shows big: a camera's detection captures
/// (`KhalaCaptureViewer`) and a snapshot (`KhalaSnapshotViewer`). Build 35.1 gave the live player its zoom; the stills
/// now get the same, from the same container (`KhalaZoomContainer`): pinch, double tap 1× → 2.5× → 4× → 1× at the
/// tap, pan with momentum while zoomed, the zoom chip to reset, swipe down at 1× to close (the picture follows the
/// finger, the backdrop fades), a tap to hide or show the chrome, and landscape as the app allows. Several stills page
/// sideways at 1× only (`KhalaStillPager`). Presented with `khalaStillCover(item:content:)`.
struct KhalaStillViewer<Accessory: View>: View {
    let title: String
    /// Under the title: "08:35 · 3 of 12".
    let subtitle: String?
    let stills: [KhalaStill]
    @Binding var index: Int
    let onClose: () -> Void
    /// Under the picture, with the chrome (the capture viewer's "Go live").
    let accessory: Accessory

    @State private var isChromeVisible = true
    @State private var zoomScale: CGFloat = 1
    @State private var zoomResetToken = 0
    @State private var dismissProgress: CGFloat = 0

    init(
        title: String,
        subtitle: String? = nil,
        stills: [KhalaStill],
        index: Binding<Int>,
        onClose: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.stills = stills
        self._index = index
        self.onClose = onClose
        self.accessory = accessory()
    }

    var body: some View {
        let showsChrome = isChromeVisible && dismissProgress == 0
        let zoomLabel = dismissProgress == 0 ? KhalaLiveZoom.label(zoomScale) : nil
        ZStack {
            // What is underneath shows through as the picture is swiped away.
            Color.black
                .opacity(1 - Double(dismissProgress))
                .ignoresSafeArea()

            KhalaStillPagerView(
                stills: stills,
                index: $index,
                resetToken: zoomResetToken,
                onTap: { isChromeVisible.toggle() },
                onZoom: { zoomScale = $0 },
                onDismissProgress: { dismissProgress = $0 },
                onDismiss: onClose
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                if showsChrome {
                    topBar
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                // As on the live player, the chip stays while the rest of the chrome is hidden.
                if let zoomLabel {
                    KhalaZoomChip(label: zoomLabel) { zoomResetToken += 1 }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                if showsChrome {
                    accessory
                        .transition(.opacity)
                }
            }
            .padding(.bottom, 16)
        }
        .statusBarHidden(!isChromeVisible)
        .persistentSystemOverlays(isChromeVisible ? .automatic : .hidden)
        .animation(.easeInOut(duration: 0.2), value: showsChrome)
        .animation(.easeInOut(duration: 0.15), value: zoomLabel)
        // VoiceOver's two-finger scrub closes, as the close button does.
        .accessibilityAction(.escape, onClose)
    }

    private var current: KhalaStill? {
        stills.indices.contains(index) ? stills[index] : stills.first
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            KhalaGlassButton(symbol: .xmark, accessibilityLabel: KhalaScreenText.close, action: onClose)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            if let image = current?.image {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview(title, image: Image(uiImage: image))
                ) {
                    Image(systemSymbol: .squareAndArrowUp)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(KhalaTheme.ink)
                        .frame(width: 44, height: 44)
                        .khalaGlass(in: Circle(), interactive: true)
                        .contentShape(Circle())
                }
                .accessibilityLabel(KhalaScreenText.share)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
    }
}

extension KhalaStillViewer where Accessory == EmptyView {
    /// A viewer with nothing under the picture (a snapshot).
    init(
        title: String,
        subtitle: String? = nil,
        stills: [KhalaStill],
        index: Binding<Int>,
        onClose: @escaping () -> Void
    ) {
        self.init(title: title, subtitle: subtitle, stills: stills, index: index, onClose: onClose) { EmptyView() }
    }
}

#Preview {
    KhalaStillViewer(
        title: "Camera",
        subtitle: "08:35 · 1 of 2",
        stills: [
            KhalaStill(id: "a", image: UIImage(systemSymbol: .photo), accessibilityLabel: "Camera, 08:35"),
            KhalaStill(id: "b", image: nil, accessibilityLabel: "Camera, 09:10"),
        ],
        index: .constant(0),
        onClose: {}
    )
}
