import Shared
import SwiftUI

/// The app's own native camera player, hosted inside a card: the same players `CameraPlayerView` shows full screen
/// (`KhalaWebKitLivePlayer` — the frontend's player, WebRTC and HLS in one page — then `CameraStreamHLSView`,
/// `CameraMJPEGPlayerView`), chosen and fallen back between exactly as it does — `CameraCapabilities.fetch` →
/// `CameraStreamPlan.players(for:)` → `CameraPlayerPlayback`. Only the full-screen chrome (navigation bar, picker,
/// close button) is left out; the card supplies its own.
///
/// The latest still (`poster`, the camera's cached `camera_proxy` frame) shows at once, so the card is never a black
/// box while the stream starts (build 19.1: "very laggy"). The WebKit page takes it as its videos' own `poster` and
/// the frame replaces it in place; until the page has it, the same still sits behind the (transparent) page.
struct KhalaCameraLivePlayer: View {
    let server: Server
    let cameraEntityId: String
    let cameraName: String?
    /// The still shown until the stream is up.
    var poster: (() async -> UIImage?)?
    /// Told which way the stream is playing — player and codec — for the LIVE badge (nil while none).
    var onPlayer: ((KhalaLivePath?) -> Void)?
    /// The host's handle for the live frame (the card's Snapshot button).
    var controller: KhalaLiveController?

    @State private var playback = CameraPlayerPlayback()
    @State private var controlsVisible = true
    @State private var showLoader = true
    @State private var posterImage: UIImage?
    /// The WebKit page's lane on screen and its codec ("WebRTC · H.265"), once it plays.
    @State private var webKitPath: KhalaLivePath?
    /// What the WebKit page runs for this camera (`KhalaLiveEngineStore.lanes`).
    @State private var lanes = KhalaLiveLanes(webRTC: true, hls: false)

    private var livePath: KhalaLivePath? {
        guard let current = playback.current else { return nil }
        return current == .webRTC ? webKitPath : KhalaLivePath(current.khalaTransport)
    }

    var body: some View {
        ZStack {
            Color.black
            // The WebKit page is transparent until its own poster or first frame: the same still behind it means
            // nothing ever flashes black in between.
            if playback.current == .webRTC, showLoader, let posterImage {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFill()
                    .allowsHitTesting(false)
            }
            Group {
                if let player = playback.current {
                    switch player {
                    case .webRTC:
                        // The frontend's player in WebKit: Apple's WebRTC (H.265-capable, unlike the bundled
                        // libwebrtc) racing WebKit's HLS, one shown.
                        KhalaWebKitLivePlayer(
                            server: server,
                            cameraEntityId: cameraEntityId,
                            cameraName: cameraName,
                            lanes: lanes,
                            fit: .cover,
                            style: .card,
                            poster: posterImage,
                            controller: controller,
                            controlsVisible: $controlsVisible,
                            showLoader: $showLoader,
                            onWebRTCUnsupported: { advance(from: .webRTC) },
                            onPath: { webKitPath = $0 }
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
                if playback.current != .webRTC, let posterImage {
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
        .onChange(of: livePath) { onPlayer?($0) }
        .task(id: cameraEntityId) {
            posterImage = nil
            posterImage = await poster?()
        }
        .task(id: cameraEntityId) {
            showLoader = true
            webKitPath = nil
            playback.clear()
            let entityId = cameraEntityId
            let capabilities = await CameraCapabilities.fetch(server: server, cameraEntityId: entityId)
            guard entityId == cameraEntityId else { return }
            // The hidden Live engine setting and this app session's WebKit failures shape the plan and the page.
            let players = CameraStreamPlan.players(for: capabilities)
            lanes = KhalaLiveEngineStore.lanes(players, cameraEntityId: entityId)
            playback.start(with: KhalaLiveEngineStore.plan(players, cameraEntityId: entityId))
        }
    }

    private func advance(from player: CameraPlayerType) {
        var advanced = playback
        guard advanced.advance(from: player) != nil else { return }
        showLoader = true
        webKitPath = nil
        playback = advanced
    }
}

extension CameraPlayerType {
    var khalaTransport: KhalaLivePath.Transport {
        switch self {
        case .webRTC: return .webRTC
        case .hls: return .hls
        case .mjpeg: return .mjpeg
        }
    }
}

extension KhalaCameraView {
    /// The LIVE badge's "WEBRTC · H.265": the player and, once known, the codec actually decoded.
    static func playerName(_ path: KhalaLivePath) -> String {
        path.label
    }
}
