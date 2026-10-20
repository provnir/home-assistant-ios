import Foundation

/// An automation that runs a device on a clock: one row of a device's "Tonight" and Schedule lists, and — when it
/// turns the device on for a known time — a window on the hot-water dial.
struct KhalaDeviceAutomation: Equatable, Identifiable {
    let automationId: String
    let name: String
    /// The automation's own `description`, when it has one.
    let description: String?
    let isEnabled: Bool
    /// Upcoming fire times inside the asked horizon, sorted.
    let fireDates: [Date]
    /// Literal trigger times (seconds after midnight), for the dial; empty for sun/entity-based ones.
    let timesOfDay: [Int]
    /// How long it runs the device when it says so (`timer_minutes`, `duration`), else nil.
    let runMinutes: Int?
    /// It acts on the device itself, rather than only sharing a helper with an automation that does.
    let targetsDevice: Bool

    var id: String { automationId }

    var toggleCall: KhalaServiceCall {
        KhalaServiceCall("automation", isEnabled ? "turn_off" : "turn_on", entityId: automationId)
    }
}
