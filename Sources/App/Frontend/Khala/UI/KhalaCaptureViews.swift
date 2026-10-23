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

/// The full-screen viewer of a camera's detection captures (build 19.1: a tap on a detection showed the live stream,
/// not what was detected), on the shared zoomable still viewer (`KhalaStillViewer`). Swipes between the camera's
/// captures of that day, oldest on the left; shares the one on screen; "Go live" leaves for the camera's live view.
/// Each page is the full-size capture, loaded for the page on screen first, then its neighbours; only the pages
/// around it stay in memory (`KhalaStillPaging`).
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
        KhalaStillViewer(
            title: request.cameraName,
            subtitle: subtitle,
            stills: shown.map { capture in
                KhalaStill(
                    id: capture.id,
                    image: images[capture.id],
                    accessibilityLabel: "\(request.cameraName), \(KhalaText.time(capture.date, calendar: calendar))"
                )
            },
            index: Binding(
                get: { currentIndex },
                set: { index in
                    if shown.indices.contains(index) { selection = shown[index].id }
                }
            ),
            onClose: onClose
        ) {
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
        }
        .task(id: request.id) {
            selection = request.capture.id
            let day = await source.captures(cameraEntityId: request.cameraEntityId, day: request.capture.date)
            captures = day.contains(request.capture) ? day : (day + [request.capture]).sorted { $0.date < $1.date }
        }
        // Again on every page turn, and once the day's list is in (the same capture, new neighbours).
        .task(id: "\(selection ?? "")#\(shown.count)") {
            await loadImages()
        }
    }

    /// The day's captures once listed; the one asked for until then.
    private var shown: [KhalaCapture] {
        captures.isEmpty ? [request.capture] : captures
    }

    private var currentIndex: Int {
        shown.firstIndex { $0.id == selection } ?? shown.firstIndex(of: request.capture) ?? 0
    }

    /// "08:35 · 3 of 12"
    private var subtitle: String {
        let index = currentIndex
        let time = KhalaText.time(shown[index].date, calendar: calendar)
        guard shown.count > 1 else { return time }
        return "\(time) · \(KhalaScreenText.position(index + 1, of: shown.count))"
    }

    /// The full-size images of the page on screen and its neighbours, in that order; the ones further away let go.
    private func loadImages() async {
        let pages = shown
        let index = currentIndex
        images = images.filter { id, _ in
            pages.firstIndex { $0.id == id }.map { KhalaStillPaging.keeps($0, around: index) } ?? false
        }
        for page in KhalaStillPaging.loadOrder(around: index, count: pages.count) {
            let capture = pages[page]
            guard images[capture.id] == nil else { continue }
            let image = await source.image(for: capture, thumbnail: false)
            guard !Task.isCancelled else { return }
            if let image { images[capture.id] = image }
        }
    }
}
