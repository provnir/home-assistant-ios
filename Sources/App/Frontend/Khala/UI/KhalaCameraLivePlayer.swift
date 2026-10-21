import Shared
import SwiftUI

/// The app's own native camera player, hosted inside a card: the same players `CameraPlayerView` shows full screen
/// (`WebRTCVideoPlayerView`, `CameraStreamHLSView`, `CameraMJPEGPlayerView`), chosen and fallen back between exactly
/// as it does — `CameraCapabilities.fetch` → `CameraStreamPlan.players(for:)` → `CameraPlayerPlayback`. Only the
/// full-screen chrome (navigation bar, picker, close button) is left out; the card supplies its own.
///
/// The latest still (`poster`, the camera's cached `camera_proxy` frame) shows at once and stays over the player
/// until the stream is up, so the card is never a black box while WebRTC negotiates (build 19.1: "very laggy").
struct KhalaCameraLivePlayer: View {
    let server: Server
    let cameraEntityId: String
    let cameraName: String?
    /// The still shown until the stream is up.
    var poster: (() async -> UIImage?)?
    /// Told which player is on (nil while none).
    var onPlayer: ((CameraPlayerType?) -> Void)?

    @State private var playback = CameraPlayerPlayback()
    @State private var controlsVisible = true
    @State private var showLoader = true
    @State private var posterImage: UIImage?

    var body: some View {
        ZStack {
            Color.black
            Group {
                if let player = playback.current {
                    switch player {
                    case .webRTC:
                        WebRTCVideoPlayerView(
                            server: server,
                            cameraEntityId: cameraEntityId,
                            cameraName: cameraName,
                            controlsVisible: $controlsVisible,
                            showLoader: $showLoader,
                            onWebRTCUnsupported: { advance(from: .webRTC) }
                        )
                    case .hls:
                        CameraStreamHLSView(
                            server: server,
                            cameraEntityId: cameraEntityId,
                            cameraName: cameraName,
                            controlsVisible: $controlsVisible,
                            onHLSUnsupported: { advance(from: .hls) }
                        )
                    case .mjpeg:
                        CameraMJPEGPlayerView(
                            server: server,
                            cameraEntityId: cameraEntityId,
                            cameraName: cameraName,
                            controlsVisible: $controlsVisible
                        )
                    }
                }
            }
            // As in `CameraPlayerView.content`: a new camera tears the old stream down before the next starts.
            .id(cameraEntityId)

            if playback.isLoaderVisible(webRTCIsLoading: showLoader) {
                if let posterImage {
                    Image(uiImage: posterImage)
                        .resizable()
                        .scaledToFill()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
        }
        // The players hide the status bar for their full-screen home; inside a card the screen keeps it.
        .statusBarHidden(false)
        .persistentSystemOverlays(.automatic)
        .clipped()
        .animation(.easeOut(duration: 0.25), value: playback.isLoaderVisible(webRTCIsLoading: showLoader))
        .onChange(of: playback.current) { onPlayer?($0) }
        .task(id: cameraEntityId) {
            posterImage = nil
            posterImage = await poster?()
        }
        .task(id: cameraEntityId) {
            showLoader = true
            playback.clear()
            let entityId = cameraEntityId
            let capabilities = await CameraCapabilities.fetch(server: server, cameraEntityId: entityId)
            guard entityId == cameraEntityId else { return }
            playback.start(with: CameraStreamPlan.players(for: capabilities))
        }
    }

    private func advance(from player: CameraPlayerType) {
        var advanced = playback
        guard advanced.advance(from: player) != nil else { return }
        showLoader = true
        playback = advanced
    }
}
