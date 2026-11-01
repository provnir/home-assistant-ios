import Foundation

/// Where a device of a kind opens (DESCRIPTORS-DESIGN.md §3, "Routing becomes a descriptor field"): the routing
/// table is `KhalaDescriptors.all`, one `route` per kind, read by `KhalaRouting` (sheet or screen) and
/// `KhalaDetailScreen` (which screen). A pin's kind — detected, from a legacy role, or picked with "Show as…" —
/// decides it, so a climate pinned with the heat role (kind water heater) still opens the water screen.
enum KhalaScreenRoute: Equatable {
    /// `KhalaTemplateScreen`: the kind's template (lights, fans, climate, covers, switches, anything else).
    case template
    /// The car screen (`KhalaCarView`): top view, Overview · Climate · Charging, wake first.
    case car
    /// The hot-water screen (`KhalaWaterView`): the boiler dial, Now · Schedule · History.
    case water
    /// The media sheet over the current screen, for the device's face player.
    case mediaSheet
    /// The camera screen of the device's camera when it has one (a doorbell, a lock on a camera's device),
    /// else the template.
    case camera
}
