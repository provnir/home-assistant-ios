import Foundation

/// The entity-level rule of a descriptor: which entities are of its kind. Reads only language-free data — the
/// domain, the device class from the state attributes, the registry's `translation_key` and capabilities parsed
/// by Home Assistant's own code — never names or ids. Of all matching descriptors the most specific wins.
struct KhalaMatch: Equatable {
    /// Empty = any domain (the generic fallback).
    var domains: Set<String>
    /// nil = any device class.
    var deviceClasses: Set<String>? = nil
    /// The registry `translation_key`; nil = any.
    var translationKeys: Set<String>? = nil
    var requires: KhalaCapabilityTest? = nil

    /// One point per constraint, so a dimmable-light rule beats a light rule and anything beats the fallback.
    var specificity: Int {
        (domains.isEmpty ? 0 : 1) + (deviceClasses == nil ? 0 : 1) + (translationKeys == nil ? 0 : 1)
            + (requires == nil ? 0 : 1)
    }

    func matches(_ entity: KhalaEntity, attributes: [String: Any]) -> Bool {
        if !domains.isEmpty, !domains.contains(entity.domain) { return false }
        if let deviceClasses, !deviceClasses.contains(entity.deviceClass ?? "") { return false }
        if let translationKeys, !translationKeys.contains(entity.translationKey ?? "") { return false }
        if let requires, !requires.passes(attributes: attributes) { return false }
        return true
    }
}
