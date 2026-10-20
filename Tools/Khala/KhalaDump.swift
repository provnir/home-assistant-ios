// Staged as `main.swift` of a throwaway executable by `linux-check.sh`: prints what Khala would show for a saved
// `GET /api/states` answer. Registry data (devices, hidden/diagnostic flags) is not part of that answer, so every
// entity stands alone here; on a phone the app database fills those in.
import Foundation
@testable import KhalaModel

let arguments = CommandLine.arguments
guard arguments.count > 1,
      let data = FileManager.default.contents(atPath: arguments[1]),
      let states = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
    print("usage: KhalaDump states.json")
    exit(2)
}

let entities: [KhalaEntity] = states.compactMap { state in
    guard let entityId = state["entity_id"] as? String, let value = state["state"] as? String else { return nil }
    let changed = (state["last_changed"] as? String).flatMap(KhalaDateParser.timestamp) ?? Date()
    return KhalaEntity(
        entityId: entityId,
        state: value,
        lastChanged: changed,
        attributes: state["attributes"] as? [String: Any] ?? [:]
    )
}

let calendar = Calendar.current
let now = Date()
let devices = KhalaDeviceCatalog.build(entities: entities, assignments: [])
let timeline = KhalaTimeline.build(
    entities: entities,
    devices: devices,
    automationConfigs: [:],
    now: now,
    calendar: calendar
)

print("entities: \(entities.count), unparsed timestamps in event.*: \(entities.filter { $0.domain == "event" && !$0.isUnavailable && $0.stateDate == nil }.count)")
print("Today · \(timeline.summary)")
for item in timeline.items {
    let marker = item.isNow ? "●" : (item.isPast ? "•" : "○")
    let subtitle = item.subtitle.map { " — \($0)" } ?? ""
    print("  \(KhalaText.time(item.date, calendar: calendar)) \(marker) [\(item.category.rawValue)] \(item.title)\(subtitle)")
}
print("Now card: \(timeline.headline)")
print("  chips: " + timeline.chips.map { "\($0.name) \($0.stateText)" }.joined(separator: " | "))
print("Devices (no registry, so each entity alone):")
for device in devices {
    print("  [\(device.category.rawValue)] \(device.name): \(device.stateText)")
}
print("Cameras: \(KhalaDeviceCatalog.cameras(in: entities).count)")
