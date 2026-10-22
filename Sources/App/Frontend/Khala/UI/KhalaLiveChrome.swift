import SwiftUI
import UIKit
import WebKit

// The live player's native shell around `KhalaWebRTCPage`: the zoom container, the controls and the info sheet.

/// Pinch and double-tap zoom with pan, momentum and edge rubber-banding, a tap for the controls, a long press for
/// the info sheet and (full screen) swipe down to close.
///
/// The zoom is a `UIScrollView` whose zooming view holds the WKWebView, not CSS driven from native gestures:
/// - the scroll view scales the web view's layer tree on the render server, so every frame of a pinch, a pan, the
///   deceleration and the bounce back past 1× or 4× runs at the display's rate with no JavaScript or IPC in the loop
///   (a CSS transform would need an `evaluateJavaScript` per gesture update, a round trip into the web content
///   process each frame);
/// - the video is a hosted layer inside that tree, sampled from the decoded frame (2688×1520 here) when scaled, so
///   zooming in shows the stream's own detail, not an upscaled screen-size bitmap;
/// - momentum, rubber-banding and `zoom(to:animated:)` are UIKit's own, the same physics as Photos.
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

    func makeUIView(context: Context) -> KhalaLiveZoomContainer {
        let container = KhalaLiveZoomContainer(webView: webView)
        configure(container)
        return container
    }

    func updateUIView(_ container: KhalaLiveZoomContainer, context: Context) {
        configure(container)
        if context.coordinator.resetToken != resetToken {
            context.coordinator.resetToken = resetToken
            container.resetZoom(animated: true)
        }
    }

    /// The container goes; the web view is the session's and leaves with it (only if it is still ours).
    static func dismantleUIView(_ container: KhalaLiveZoomContainer, coordinator: Coordinator) {
        container.detachWebView()
    }

    private func configure(_ container: KhalaLiveZoomContainer) {
        container.allowsSwipeDown = allowsSwipeDown
        container.onTap = onTap
        container.onLongPress = onLongPress
        container.onZoom = onZoom
        container.onDismissProgress = onDismissProgress
        container.onDismiss = onDismiss
    }
}

final class KhalaLiveZoomContainer: UIView, UIScrollViewDelegate {
    var allowsSwipeDown = false
    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?
    var onZoom: ((CGFloat) -> Void)?
    var onDismissProgress: ((CGFloat) -> Void)?
    var onDismiss: (() -> Void)?

    private let scrollView = UIScrollView()
    private let content = UIView()
    private weak var webView: WKWebView?
    private var laidOutSize: CGSize = .zero
    private var reportedScale: CGFloat = 1
    private let dismissGate = KhalaGestureGate()
    private lazy var dismissPan: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = dismissGate
        return pan
    }()

    init(webView: WKWebView) {
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = true

        scrollView.delegate = self
        scrollView.minimumZoomScale = KhalaLiveZoom.minimum
        scrollView.maximumZoomScale = KhalaLiveZoom.maximum
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.scrollsToTop = false
        scrollView.decelerationRate = .normal
        scrollView.backgroundColor = .clear
        // Unzoomed, a one-finger drag belongs to whatever is around the player (the screen's scroll, swipe down).
        scrollView.panGestureRecognizer.isEnabled = false
        addSubview(scrollView)
        content.backgroundColor = .clear
        scrollView.addSubview(content)

        self.webView = webView
        webView.removeFromSuperview()
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.addSubview(webView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        addGestureRecognizer(longPress)
        dismissGate.shouldBegin = { [weak self] recognizer in
            self?.shouldBeginDismiss(recognizer as? UIPanGestureRecognizer) ?? false
        }
        addGestureRecognizer(dismissPan)

        accessibilityTraits = .image
        accessibilityHint = "Double tap and hold for stream details"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        // A new size (rotation, the card resizing) starts unzoomed: the old zoom rectangle means nothing in it.
        scrollView.zoomScale = KhalaLiveZoom.minimum
        scrollView.frame = bounds
        content.frame = CGRect(origin: .zero, size: bounds.size)
        webView?.frame = content.bounds
        scrollView.contentSize = bounds.size
        scrollView.contentOffset = .zero
        zoomChanged()
    }

    func resetZoom(animated: Bool) {
        scrollView.setZoomScale(KhalaLiveZoom.minimum, animated: animated)
    }

    func detachWebView() {
        if let webView, webView.superview === content {
            webView.removeFromSuperview()
        }
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        content
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        zoomChanged()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        zoomChanged()
    }

    private func zoomChanged() {
        let scale = scrollView.zoomScale
        scrollView.panGestureRecognizer.isEnabled = KhalaLiveZoom.isZoomed(scale)
        // The chip shows tenths; spare SwiftUI a re-render for every sub-pixel step of a pinch.
        guard abs(scale - reportedScale) >= 0.05 || (scale == KhalaLiveZoom.minimum && reportedScale != scale) else {
            return
        }
        reportedScale = scale
        onZoom?(scale)
    }

    // MARK: Gestures

    @objc private func handleTap() {
        onTap?()
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        let next = KhalaLiveZoom.nextStep(after: scrollView.zoomScale)
        guard next > KhalaLiveZoom.minimum else {
            resetZoom(animated: true)
            return
        }
        let point = recognizer.location(in: content)
        scrollView.zoom(to: KhalaLiveZoom.zoomRect(scale: next, center: point, in: content.bounds.size), animated: true)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onLongPress?()
    }

    /// Full screen, unzoomed: the picture follows the finger down and either closes or springs back.
    @objc private func handleDismissPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = max(recognizer.translation(in: self).y, 0)
        switch recognizer.state {
        case .changed:
            let progress = KhalaLiveZoom.dismissProgress(translation: translation, height: bounds.height)
            scrollView.transform = CGAffineTransform(translationX: 0, y: translation)
                .scaledBy(x: 1 - progress * 0.15, y: 1 - progress * 0.15)
            onDismissProgress?(progress)
        case .ended:
            if KhalaLiveZoom.shouldDismiss(translation: translation, velocity: recognizer.velocity(in: self).y) {
                onDismiss?()
            } else {
                springBack()
            }
        case .cancelled, .failed:
            springBack()
        default:
            break
        }
    }

    private func springBack() {
        UIView.animate(
            withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.scrollView.transform = .identity
        }
        onDismissProgress?(0)
    }

    /// Only full screen, only unzoomed, only a drag that starts downwards.
    private func shouldBeginDismiss(_ pan: UIPanGestureRecognizer?) -> Bool {
        guard let pan, allowsSwipeDown, !KhalaLiveZoom.isZoomed(scrollView.zoomScale) else { return false }
        let velocity = pan.velocity(in: self)
        return velocity.y > 0 && velocity.y > abs(velocity.x)
    }
}

/// A gesture delegate that only answers whether a recognizer may begin (kept apart from the view, whose own
/// `gestureRecognizerShouldBegin(_:)` has the same selector).
private final class KhalaGestureGate: NSObject, UIGestureRecognizerDelegate {
    var shouldBegin: ((UIGestureRecognizer) -> Bool)?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        shouldBegin?(gestureRecognizer) ?? false
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
                Button(action: onResetZoom) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.magnifyingglass")
                        Text(zoomLabel).monospacedDigit()
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(.black.opacity(0.55), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zoom \(zoomLabel), reset")
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
