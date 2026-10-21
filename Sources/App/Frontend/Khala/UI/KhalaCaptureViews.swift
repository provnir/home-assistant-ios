import SFSafeSymbols
import Shared
import SwiftUI
import UIKit

/// A detection to show the capture of: the camera that saw it and when.
struct KhalaCaptureRef: Equatable, Hashable {
    let cameraEntityId: String
    let date: Date
}

/// What the shell's full-screen capture viewer opens on.
struct KhalaCaptureViewerRequest: Equatable, Identifiable {
    let cameraEntityId: String
    let cameraName: String
    /// The capture to start on; the viewer swipes through the camera's other captures of that day.
    let capture: KhalaCapture

    var id: String { capture.id }
}

/// A detection card's thumbnail: the capture saved for the detection (`KhalaCaptureSource`), else the tinted
/// placeholder. Nothing streams.
struct KhalaCaptureThumbnail: View {
    let ref: KhalaCaptureRef?
    let category: KhalaCategory
    var cornerRadius: CGFloat = 14

    @Environment(\.khalaCaptures) private var captures
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(KhalaTheme.thumbnail)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.easeOut(duration: 0.2), value: image != nil)
            .task(id: ref) {
                image = nil
                guard let ref, let captures,
                      let capture = await captures.capture(cameraEntityId: ref.cameraEntityId, near: ref.date) else { return }
                image = await captures.image(for: capture, thumbnail: true)
            }
            .accessibilityHidden(true)
    }
}

/// The full-screen still viewer of a camera's detection captures (build 19.1: a tap on a detection showed the
/// live stream, not what was detected). Swipes between the camera's captures of that day, oldest on the left;
/// shares the one on screen; "Go live" leaves for the camera's live view.
struct KhalaCaptureViewer: View {
    let request: KhalaCaptureViewerRequest
    let source: KhalaCaptureSource
    let calendar: Calendar
    let onClose: () -> Void
    let onLive: () -> Void

    @State private var captures: [KhalaCapture] = []
    @State private var selection: String?
    @State private var images: [String: UIImage] = [:]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(shown) { capture in
                    page(capture)
                        .tag(Optional(capture.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
        }
        .statusBarHidden(false)
        .task(id: request.id) {
            selection = request.capture.id
            let day = await source.captures(cameraEntityId: request.cameraEntityId, day: request.capture.date)
            captures = day.contains(request.capture) ? day : (day + [request.capture]).sorted { $0.date < $1.date }
        }
    }

    /// The day's captures once listed; the one asked for until then.
    private var shown: [KhalaCapture] {
        captures.isEmpty ? [request.capture] : captures
    }

    private var current: KhalaCapture {
        shown.first { $0.id == selection } ?? request.capture
    }

    private func page(_ capture: KhalaCapture) -> some View {
        ZStack {
            if let image = images[capture.id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("\(request.cameraName), \(KhalaText.time(capture.date, calendar: calendar))")
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: capture.id) {
            guard images[capture.id] == nil else { return }
            if let image = await source.image(for: capture, thumbnail: false) {
                images[capture.id] = image
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            KhalaGlassButton(symbol: .xmark, accessibilityLabel: KhalaScreenText.close, action: onClose)
            VStack(alignment: .leading, spacing: 1) {
                Text(request.cameraName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            if let image = images[current.id] {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview(request.cameraName, image: Image(uiImage: image))
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

    /// "08:35 · 3 of 12"
    private var subtitle: String {
        let time = KhalaText.time(current.date, calendar: calendar)
        guard shown.count > 1, let index = shown.firstIndex(of: current) else { return time }
        return "\(time) · \(KhalaScreenText.position(index + 1, of: shown.count))"
    }

    private var bottomBar: some View {
        Button(action: onLive) {
            Label(KhalaScreenText.goLive, systemSymbol: .videoFill)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KhalaTheme.ink)
                .padding(.horizontal, 20)
                .frame(height: 48)
                .khalaGlass(in: Capsule(), interactive: true)
                .contentShape(Capsule())
        }
        .buttonStyle(KhalaPressStyle())
        .padding(.bottom, 16)
    }
}
