import SwiftUI
import UIKit
import WebKit

// The live player's native shell around `KhalaWebRTCPage`: the zoom view, the controls and the info sheet.

/// The live player's zoom: its WKWebView in the shared zoom container (`KhalaZoomContainer`, which the still viewer
/// uses too) — pinch and double-tap zoom with pan, momentum and edge rubber-banding, a tap for the controls, a long
/// press for the info sheet and (full screen) swipe down to close.
struct KhalaLiveZoomView: UIViewRepresentable {
    let webView: WKWebView
    var allowsSwipeDown: Bool
    /// Changed by the host to zoom back to 1× (the zoom chip).
    var resetToken: Int
    var onTap: () -> Void
    var onLongPress: () -> Void
    var onZoom: (CGFloat) -> Void
    var onDismissProgress: (CGFloat) -> Void
    var onDismiss: () -> Void

    final class Coordinator {
        var resetToken = 0
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.resetToken = resetToken
        return coordinator
    }

    func makeUIView(context: Context) -> KhalaZoomContainer {
        let container = KhalaZoomContainer(hosting: webView)
        container.accessibilityHint = "Double tap and hold for stream details"
        configure(container)
        return container
    }

    func updateUIView(_ container: KhalaZoomContainer, context: Context) {
        configure(container)
        if context.coordinator.resetToken != resetToken {
            context.coordinator.resetToken = resetToken
            container.resetZoom(animated: true)
        }
    }

    /// The container goes; the web view is the session's and leaves with it (only if it is still ours).
    static func dismantleUIView(_ container: KhalaZoomContainer, coordinator: Coordinator) {
        container.detachHosted()
    }

    private func configure(_ container: KhalaZoomContainer) {
        container.allowsSwipeDown = allowsSwipeDown
        container.onTap = onTap
        container.onLongPress = onLongPress
        container.onZoom = onZoom
        container.onDismissProgress = onDismissProgress
        container.onDismiss = onDismiss
    }
}

/// The player's buttons. Card: mute and picture in picture in a corner (Snapshot is the card's own button).
/// Full screen: mute, picture in picture, snapshot and info along the bottom. Both: the zoom chip, which zooms back
/// to 1× when tapped.
struct KhalaLiveControls: View {
    let style: KhalaWebKitLivePlayer.Style
    let isVisible: Bool
    let isMuted: Bool
    let isPictureInPicture: Bool
    let isPlaying: Bool
    let isTakingSnapshot: Bool
    let zoomLabel: String?
    let onMute: () -> Void
    let onPictureInPicture: () -> Void
    let onSnapshot: () -> Void
    let onInfo: () -> Void
    let onResetZoom: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            if let zoomLabel {
                KhalaZoomChip(label: zoomLabel, action: onResetZoom)
                    .frame(maxWidth: .infinity, alignment: style == .card ? .leading : .center)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            if isVisible {
                HStack(spacing: style == .card ? 8 : 18) {
                    if style == .card { Spacer(minLength: 0) }
                    button(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           label: isMuted ? "Unmute" : "Mute", action: onMute)
                    button(isPictureInPicture ? "pip.exit" : "pip.enter",
                           label: "Picture in picture", action: onPictureInPicture)
                        .disabled(!isPlaying)
                    if style == .fullScreen {
                        button("camera.fill", label: "Snapshot", action: onSnapshot)
                            .disabled(!isPlaying || isTakingSnapshot)
                        button("info.circle", label: "Stream details", action: onInfo)
                    }
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            }
        }
        .padding(style == .card ? 10 : 20)
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .animation(.easeInOut(duration: 0.15), value: zoomLabel)
    }

    private func button(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        let size: CGFloat = style == .card ? 32 : 46
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: style == .card ? 13 : 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The long-press sheet: path, codec, resolution, frame rate, bitrate, round trip and the rest, read once a second.
struct KhalaLiveInfoSheet: View {
    @ObservedObject var session: KhalaWebKitLiveSession
    @Environment(\.dismiss) private var dismiss
    @State private var stats: KhalaLiveStats?

    var body: some View {
        NavigationStack {
            List {
                if let stats {
                    ForEach(stats.rows, id: \.self) { row in
                        HStack {
                            Text(row.title)
                            Spacer()
                            Text(row.value)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(session.isLoading ? "Connecting…" : "Measuring…")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Stream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(KhalaScreenText.close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            // The first reading has no rates; the next one, a second later, does.
            while !Task.isCancelled {
                if let reading = await session.stats() { stats = reading }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}
