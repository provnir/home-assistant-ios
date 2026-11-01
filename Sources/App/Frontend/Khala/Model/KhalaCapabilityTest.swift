import Foundation
import Shared

/// A capability a descriptor's match can require, read with Home Assistant's own parsers from the app's `Shared`
/// module (`LightCapabilities`, `CoverCapabilities`, …) — never from names or ids. On Linux the same upstream files
/// are staged by `Tools/Khala/linux-check.sh` behind a small `HAEntity` shim, so the tests run the real parsers.
enum KhalaCapabilityTest: String, Equatable, CaseIterable {
    case lightBrightness
    case lightColorTemp
    case lightColor
    case coverSetPosition
    case coverStop
    case lockOpen
    case fanSetSpeed
    case vacuumCleanArea
    /// A group entity (`light.*` group, `switch` group…): it lists its members in `entity_id`.
    case entityGroup

    func passes(attributes: [String: Any]) -> Bool {
        switch self {
        case .lightBrightness: return LightCapabilities(attributes: attributes).supportsBrightness
        case .lightColorTemp: return LightCapabilities(attributes: attributes).supportsColorTemp
        case .lightColor: return LightCapabilities(attributes: attributes).supportsColor
        case .coverSetPosition: return CoverCapabilities(attributes: attributes).supportsSetPosition
        case .coverStop: return CoverCapabilities(attributes: attributes).supportsStop
        case .lockOpen: return LockCapabilities(attributes: attributes).supportsOpen
        case .fanSetSpeed: return FanCapabilities(attributes: attributes).supportsSpeedPercentage
        case .vacuumCleanArea: return VacuumCapabilities(attributes: attributes).supportsCleanArea
        case .entityGroup: return !KhalaValue.list(attributes["entity_id"]).isEmpty
        }
    }
}
