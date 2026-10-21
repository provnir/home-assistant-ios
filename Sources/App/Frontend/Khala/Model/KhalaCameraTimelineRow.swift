import Foundation

/// One row of a camera's "Today on <camera>" timeline besides Now: one of its clock-driven automations still to run,
/// or one of today's detections.
enum KhalaCameraTimelineRow: Equatable, Identifiable {
    case automation(KhalaDeviceAutomation)
    case detection(KhalaDetection)

    var id: String {
        switch self {
        case let .automation(automation): return "automation:\(automation.id)"
        case let .detection(detection): return "detection:\(detection.id)"
        }
    }

    /// The automation's next run, or when the detection happened.
    var date: Date {
        switch self {
        case let .automation(automation): return automation.fireDates.first ?? .distantFuture
        case let .detection(detection): return detection.date
        }
    }

    /// Newest on top: automations (furthest first), Now, detections (latest first).
    static func order(
        upcoming: [KhalaDeviceAutomation],
        past: [KhalaDetection]
    ) -> KhalaTimelineOrder<KhalaCameraTimelineRow> {
        KhalaTimelineOrder(
            upcoming: upcoming.filter { !$0.fireDates.isEmpty }.map(Self.automation),
            past: past.map(Self.detection),
            date: \.date,
            showsNow: true
        )
    }
}
