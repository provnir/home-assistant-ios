import Foundation

/// How a kind names a whole registry device (DESCRIPTORS-DESIGN.md §1, "Choosing a device's descriptor").
enum KhalaDeviceRule: Equatable {
    /// The device's best entity of this kind becomes its face.
    case face
    /// The device is this kind when it has every domain in `all` and at least one in `any` (a car: a tracker plus a
    /// lock or a climate; phones have trackers but no locks).
    case composite(all: Set<String>, any: Set<String>)

    /// Whether a device with these domains passes a composite rule; a `face` rule is decided per entity instead.
    func isMet(byDomains domains: Set<String>) -> Bool {
        switch self {
        case .face: return false
        case let .composite(all, any): return all.isSubset(of: domains) && !any.isDisjoint(with: domains)
        }
    }
}
