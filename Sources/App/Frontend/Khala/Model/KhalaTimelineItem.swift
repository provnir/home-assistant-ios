import Foundation

/// One row of the Today timeline.
struct KhalaTimelineItem: Equatable, Identifiable {
    enum Kind: Equatable {
        case sunrise
        case sunset
        /// A camera-side detection (`event.*` with device class motion/doorbell) that happened today.
        case detection(eventEntityId: String, cameraEntityId: String?)
        /// The live "Now" row; its card shows `KhalaTimeline.headline` and `chips`.
        case now
        /// An enabled automation's next time or sun trigger.
        case scheduled(automationEntityId: String)
        /// A `sensor` with device class `timestamp` pointing later today (charge done, next alarm, ...).
        case timestamp(entityId: String)
    }

    let id: String
    let date: Date
    let kind: Kind
    let title: String
    let subtitle: String?
    let category: KhalaCategory
    /// Before (or at) the moment the timeline was built. The Now row is neither past nor upcoming.
    let isPast: Bool
    /// The entity a tap opens (more-info, or the camera player for detections), if any.
    let targetEntityId: String?

    var isNow: Bool { kind == .now }
}
