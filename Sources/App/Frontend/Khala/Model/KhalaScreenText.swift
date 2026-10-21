import Foundation

/// Copy of the device screens (camera, car, hot water, media, generic), English for now like `KhalaText`, kept apart
/// so the two can move to `L10n` independently.
enum KhalaScreenText {
    static let back = "Back"
    static let more = "More"
    static let media = "Media"
    static let close = "Close"
    static let clear = "Clear"
    static let clearToday = "All clear today"
    static let allCameras = "All cameras"
    static let chooseCamera = "Choose camera"
    static let live = "Live"
    static let events = "Events"
    static let settings = "Settings"
    static let snapshot = "Snapshot"
    static let clips = "Clips"
    static let mute = "Mute alerts"
    static let unmute = "Unmute alerts"
    static let fullScreen = "Full screen"
    static let watching = "Watching"
    static let noDetections = "Nothing detected"
    static let noDetectionsYet = "No detections in the last 7 days."
    static let loading = "Loading…"
    static let entityId = "Entity"
    static let state = "State"
    static let stream = "Live stream"
    static let stillsOnly = "Stills only"
    static let lastChanged = "Last changed"
    static let detectionSources = "Detection sources"
    static let attributes = "Attributes"
    static let model = "Model"
    static let saveSnapshot = "Share snapshot"
    static let snapshotFailed = "Couldn't get a snapshot from Home Assistant."

    static let overview = "Overview"
    static let climate = "Climate"
    static let charging = "Charging"
    static let recent = "Recent"
    static let asleep = "Asleep · wake"
    static let awake = "Awake"
    static let wake = "Wake"
    static let atHome = "At home"
    static let away = "Away"
    static let target = "Target"
    static let inside = "Inside"
    static let outside = "Outside"
    static let start = "Start"
    static let stop = "Stop"
    static let chargeLimit = "Charge limit"
    static let chargeCurrent = "Charge current"
    static let chargerPower = "Charger power"
    static let fullAt = "Full at"
    static let noClimate = "This car reports no climate control."
    static let arrived = "Arrived"
    static let left = "Left"
    static let yesterday = "yesterday"
    static let confirm = "Confirm"
    static let cancel = "Cancel"

    static let now = "Now"
    static let schedule = "Schedule"
    static let history = "History"
    static let tonight = "Tonight"
    static let heatNow = "Heat now"
    static let turnOff = "Turn off"
    static let sunsOnIt = "Sun’s on it"
    static let heating = "Heating"
    static let noSchedule = "No automation runs this device on a clock."
    static let noHistory = "Not on in the last 7 days."
    static let ongoing = "now"
    static let tomorrow = "Tomorrow"

    static let power = "Power"
    static let volume = "VOLUME"
    static let source = "SOURCE"
    static let soundMode = "Sound mode"
    static let on = "On"
    static let off = "Off"

    static let members = "Entities"
    static let unknownDevice = "This device is no longer in Home Assistant."

    static func limit(_ text: String) -> String { "Limit \(text)" }

    static let updating = "Updating…"
    static let share = "Share"
    static let goLive = "Go live"

    /// "3 of 12"
    static func position(_ index: Int, of count: Int) -> String { "\(index) of \(count)" }

    /// "Updated just now", "Updated 4 min ago", "Updated 3 h ago", "Updated 2 d ago": when a device's data last
    /// arrived (`KhalaEntityRefresh.lastUpdated`).
    static func updated(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "Updated just now"
        case ..<3600: return "Updated \(Int(seconds / 60)) min ago"
        case ..<86400: return "Updated \(Int(seconds / 3600)) h ago"
        default: return "Updated \(Int(seconds / 86400)) d ago"
        }
    }

    static func heatNow(minutes: Int?) -> String {
        guard let minutes else { return heatNow }
        return "\(heatNow) · \(minutes) min"
    }

    static func minutes(_ minutes: Int) -> String { "\(minutes) min" }

    static func todayOn(_ name: String) -> String { "Today on \(name)" }

    static func left(_ remaining: TimeInterval) -> String {
        "\(KhalaText.duration(remaining)) left"
    }

    static func runs(_ minutes: Int) -> String { "Runs \(minutes) min" }

    static func confirmAction(_ title: String) -> String { "\(title)?" }

    /// Words for a car's charging state (`sensor.*_charging` enum).
    static func chargingState(_ state: String) -> String {
        switch state {
        case "disconnected", "stopped", "no_power": return "Not charging"
        case "starting": return "Starting to charge"
        case "charging": return "Charging"
        case "complete": return "Charged"
        default: return KhalaText.humanized(state: state)
        }
    }
}
