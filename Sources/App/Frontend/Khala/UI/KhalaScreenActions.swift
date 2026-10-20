import Foundation
import HAKit
import PromiseKit
import Shared
import UIKit

/// Sends what the device screens decide over the app's own HAKit websocket connection — the same
/// `connection.send(.init(type: .webSocket(...), data:))` pattern `CameraCapabilities.fetch` and
/// `KhalaHomeViewModel` use — and reads the recorder history and camera stills they show.
struct KhalaScreenActions {
    let server: Server

    /// Performs a `call_service`; true when Home Assistant accepted it. Failures are logged and felt (haptic).
    @MainActor
    @discardableResult
    func perform(_ call: KhalaServiceCall) async -> Bool {
        guard let api = Current.api(for: server) else { return false }
        let ok: Bool = await withCheckedContinuation { continuation in
            api.connection.send(.init(
                type: .webSocket("call_service"),
                data: ["domain": call.domain, "service": call.service, "service_data": call.data]
            )) { result in
                switch result {
                case .success:
                    continuation.resume(returning: true)
                case let .failure(error):
                    Current.Log.error("Khala: \(call.name) failed: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                }
            }
        }
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(ok ? .success : .error)
        return ok
    }

    /// Recorded states of `entityIds` since `start`, with attributes (event types), every change included.
    /// `history/history_during_period`: HA core `components/history/websocket_api.py`.
    @MainActor
    func history(entityIds: [String], since start: Date) async -> [String: [KhalaHistoryState]] {
        guard !entityIds.isEmpty, let api = Current.api(for: server) else { return [:] }
        let formatter = ISO8601DateFormatter()
        return await withCheckedContinuation { continuation in
            api.connection.send(.init(
                type: .webSocket("history/history_during_period"),
                data: [
                    "start_time": formatter.string(from: start),
                    "entity_ids": entityIds,
                    "include_start_time_state": true,
                    "significant_changes_only": false,
                    "minimal_response": false,
                    "no_attributes": false,
                ]
            )) { result in
                switch result {
                case let .success(data):
                    guard case let .dictionary(response) = data else {
                        continuation.resume(returning: [:])
                        return
                    }
                    continuation.resume(returning: KhalaHistory.parse(response))
                case let .failure(error):
                    Current.Log.info("Khala: no history for \(entityIds): \(error.localizedDescription)")
                    continuation.resume(returning: [:])
                }
            }
        }
    }

    /// A still from `camera_proxy`, as `CameraPlayerView`'s picker fetches its thumbnails.
    @MainActor
    func snapshot(cameraEntityId: String) async -> UIImage? {
        guard let api = Current.api(for: server) else { return nil }
        do {
            return try await api.getCameraSnapshot(cameraEntityID: cameraEntityId).asyncValue()
        } catch {
            Current.Log.error("Khala: no snapshot for \(cameraEntityId): \(error)")
            return nil
        }
    }

    /// A small cached still for grid tiles, shared with the camera player's picker cache.
    @MainActor
    func thumbnail(cameraEntityId: String) async -> UIImage? {
        let cache = CameraPickerSnapshotCache.shared
        let key = CameraPickerSnapshotCache.Key(serverId: server.identifier.rawValue, entityId: cameraEntityId)
        if let image = cache.image(for: key) { return image }
        guard cache.shouldFetch(key) else { return nil }
        guard let image = await snapshot(cameraEntityId: cameraEntityId) else {
            cache.recordFailure(for: key)
            return nil
        }
        let thumbnail = await image.byPreparingThumbnail(ofSize: CGSize(width: 480, height: 270)) ?? image
        cache.store(thumbnail, for: key)
        return thumbnail
    }
}
