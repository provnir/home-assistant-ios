import Alamofire
import Foundation
import HAKit
import Shared
import SwiftUI
import UIKit

/// Where the still of a camera detection comes from (build 19.1: "still doesn't show a capture of the detection").
/// Detection cards on Today, the camera's Today timeline and its Events tab ask it for the capture nearest a
/// detection; the full-screen viewer (`KhalaCaptureViewer`) for every capture of that camera on that day.
@MainActor
protocol KhalaCaptureSource: AnyObject {
    /// The captures of a camera on the server's day holding `date`, oldest first; empty when there are none.
    func captures(cameraEntityId: String, day date: Date) async -> [KhalaCapture]
    /// The capture taken for a detection of `cameraEntityId` at `date`, if one was saved.
    func capture(cameraEntityId: String, near date: Date) async -> KhalaCapture?
    /// The capture's image: small for cards, full size for the viewer. Cached.
    func image(for capture: KhalaCapture, thumbnail: Bool) async -> UIImage?
    /// A file to share, when the capture's image is loaded.
    func imageData(for capture: KhalaCapture) async -> Data?
}

/// Captures saved into a media folder Home Assistant serves through its media source (`media_dirs` in
/// `configuration.yaml`): `media_source/browse_media` lists the day folders and their files,
/// `media_source/resolve_media` signs a file's URL (HA core `components/media_source/__init__.py`, websocket
/// commands `browse_media` / `resolve_media`). Authenticated, and generic: the folder is found on its own
/// (`KhalaCaptureIndex.looksLikeCaptureRoot`) unless `config.rootId` names it, file names are read with
/// `config.filePattern`, times in the server's own time zone (`get_config`).
@MainActor
final class KhalaMediaSourceCaptures: KhalaCaptureSource {
    let server: Server
    let config: KhalaCaptureConfig

    /// Unresolved until the first lookup; then the captures folder, or nil when the server has none.
    private var root: String??
    private var rootLookup: Task<String?, Never>?
    private var timeZone: TimeZone?
    /// Day folder id → its captures and when they were listed. Past days are final; today is listed again after
    /// `todayLifetime`.
    private var days: [String: (captures: [KhalaCapture], listed: Date)] = [:]
    private var dayLookups: [String: Task<[KhalaCapture], Never>] = [:]
    private let images = NSCache<NSString, UIImage>()
    private let files = NSCache<NSString, NSData>()

    private static let todayLifetime: TimeInterval = 20
    /// How long a signed URL is asked to stay valid.
    private static let signatureLifetime = 600

    init(server: Server, config: KhalaCaptureConfig = .standard) {
        self.server = server
        self.config = config
        images.countLimit = 120
        files.countLimit = 12
    }

    // MARK: - KhalaCaptureSource

    func captures(cameraEntityId: String, day date: Date) async -> [KhalaCapture] {
        let camera = KhalaCaptureIndex.objectId(of: cameraEntityId).lowercased()
        return await dayCaptures(for: date).filter { $0.cameraObjectId == camera }
    }

    func capture(cameraEntityId: String, near date: Date) async -> KhalaCapture? {
        // A detection just before midnight may be saved just after it: look at the neighbouring day too.
        var candidates = await dayCaptures(for: date)
        let zone = await serverTimeZone()
        for neighbour in [date.addingTimeInterval(-config.matchWindow), date.addingTimeInterval(config.matchWindow)] {
            if KhalaCaptureIndex.dayFolder(for: neighbour, config: config, timeZone: zone)
                != KhalaCaptureIndex.dayFolder(for: date, config: config, timeZone: zone) {
                candidates += await dayCaptures(for: neighbour)
            }
        }
        return KhalaCaptureIndex.match(cameraEntityId: cameraEntityId, date: date, in: candidates, config: config)
    }

    func image(for capture: KhalaCapture, thumbnail: Bool) async -> UIImage? {
        let key = (thumbnail ? "t:" : "f:") + capture.mediaContentId
        if let image = images.object(forKey: key as NSString) { return image }
        guard let data = await imageData(for: capture), let image = UIImage(data: data) else { return nil }
        let shown: UIImage
        if thumbnail {
            shown = await image.byPreparingThumbnail(ofSize: CGSize(width: 256, height: 192)) ?? image
        } else {
            shown = await image.byPreparingForDisplay() ?? image
        }
        images.setObject(shown, forKey: key as NSString)
        return shown
    }

    func imageData(for capture: KhalaCapture) async -> Data? {
        if let data = files.object(forKey: capture.mediaContentId as NSString) { return data as Data }
        guard let url = await resolve(capture.mediaContentId), let api = Current.api(for: server) else { return nil }
        let data: Data? = await withCheckedContinuation { continuation in
            // The API's own session: the server's TLS exceptions and client certificate apply, as for snapshots.
            api.manager.request(url).validate().responseData { response in
                switch response.result {
                case let .success(data): continuation.resume(returning: data)
                case let .failure(error):
                    Current.Log.info("Khala: capture not loaded: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
        if let data { files.setObject(data as NSData, forKey: capture.mediaContentId as NSString) }
        return data
    }

    // MARK: - Days

    private func dayCaptures(for date: Date) async -> [KhalaCapture] {
        guard let root = await captureRoot() else { return [] }
        let zone = await serverTimeZone()
        let folder = KhalaCaptureIndex.dayFolderId(rootId: root, date: date, config: config, timeZone: zone)
        let isToday = KhalaCaptureIndex.dayFolder(for: Current.date(), config: config, timeZone: zone)
            == KhalaCaptureIndex.dayFolder(for: date, config: config, timeZone: zone)
        if let cached = days[folder],
           !isToday || Current.date().timeIntervalSince(cached.listed) < Self.todayLifetime {
            return cached.captures
        }
        if let lookup = dayLookups[folder] { return await lookup.value }
        let lookup = Task { @MainActor [config] () -> [KhalaCapture] in
            guard let response = await browse(folder),
                  let day = KhalaCaptureIndex.day(ofFolder: KhalaCaptureIndex.lastComponent(of: folder), config: config,
                                                  timeZone: zone) else {
                return []
            }
            return KhalaCaptureIndex.captures(
                in: KhalaMediaNode.children(of: response), day: day, config: config, timeZone: zone
            )
        }
        dayLookups[folder] = lookup
        let captures = await lookup.value
        dayLookups[folder] = nil
        days[folder] = (captures, Current.date())
        return captures
    }

    // MARK: - Finding the folder

    private func captureRoot() async -> String? {
        if let root { return root }
        if let rootLookup { return await rootLookup.value }
        let lookup = Task { @MainActor () -> String? in
            if let configured = config.rootId { return configured }
            return await findRoot()
        }
        rootLookup = lookup
        let found = await lookup.value
        root = .some(found)
        rootLookup = nil
        if found == nil { Current.Log.info("Khala: no detection captures folder among the media sources") }
        return found
    }

    /// The media-source folder holding day folders: the top level (one media dir is listed straight away), else
    /// one of the media dirs under it.
    private func findRoot() async -> String? {
        let zone = await serverTimeZone()
        guard let top = await browse(KhalaCaptureIndex.mediaSourceRoot) else { return nil }
        let children = KhalaMediaNode.children(of: top)
        if let root = KhalaCaptureIndex.root(of: children, config: config, timeZone: zone) { return root }
        for folder in children.filter(\.canExpand).prefix(8) {
            guard let response = await browse(folder.mediaContentId) else { continue }
            if let root = KhalaCaptureIndex.root(of: KhalaMediaNode.children(of: response), config: config, timeZone: zone) {
                return root
            }
        }
        return nil
    }

    // MARK: - Websocket

    private func serverTimeZone() async -> TimeZone {
        if let timeZone { return timeZone }
        let zone: TimeZone = await withCheckedContinuation { continuation in
            guard let api = Current.api(for: server) else { return continuation.resume(returning: .current) }
            api.connection.send(.init(type: .webSocket("get_config"))) { result in
                if case let .success(.dictionary(config)) = result,
                   let name = config["time_zone"] as? String, let zone = TimeZone(identifier: name) {
                    continuation.resume(returning: zone)
                } else {
                    continuation.resume(returning: .current)
                }
            }
        }
        timeZone = zone
        return zone
    }

    private func browse(_ mediaContentId: String) async -> [String: Any]? {
        guard let api = Current.api(for: server) else { return nil }
        return await withCheckedContinuation { continuation in
            api.connection.send(.init(
                type: .webSocket("media_source/browse_media"),
                data: ["media_content_id": mediaContentId]
            )) { result in
                if case let .success(.dictionary(response)) = result {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// The file's signed URL, absolute on the server's active URL.
    private func resolve(_ mediaContentId: String) async -> URL? {
        guard let api = Current.api(for: server) else { return nil }
        let path: String? = await withCheckedContinuation { continuation in
            api.connection.send(.init(
                type: .webSocket("media_source/resolve_media"),
                data: ["media_content_id": mediaContentId, "expires": Self.signatureLifetime]
            )) { result in
                if case let .success(.dictionary(response)) = result, let url = response["url"] as? String {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
        guard let path else { return nil }
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
        guard let base = await server.activeURL() else { return nil }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }
}

// MARK: - Environment

private struct KhalaCaptureSourceKey: EnvironmentKey {
    static let defaultValue: KhalaCaptureSource? = nil
}

extension EnvironmentValues {
    /// The shell's capture source; nil in previews (cards keep their placeholder).
    var khalaCaptures: KhalaCaptureSource? {
        get { self[KhalaCaptureSourceKey.self] }
        set { self[KhalaCaptureSourceKey.self] = newValue }
    }
}
