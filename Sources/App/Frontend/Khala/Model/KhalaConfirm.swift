import Foundation

/// A control that asks before acting. The copy comes from `KhalaScreenText`, never built from entity names.
enum KhalaConfirm: Hashable {
    case unlock
    /// Opening a cover or a lock; the device class (`garage`, `gate`, `door`) picks the wording.
    case open(deviceClass: String?)
}
