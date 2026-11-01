import Foundation

/// One entry of the hints file (`Resources/khala-hints.json`, DESCRIPTORS-DESIGN.md §1, "Integration knowledge is
/// data only"): what an integration's entity is FOR, keyed on what the registry says about it — its `platform` and,
/// when given, its `domain` and `translation_key` — never on an entity's name or id. Without a hint an entity falls
/// back to its domain and device class: generic, but correct.
///
/// JSON fields (all but `platform` optional):
/// - `platform`, `domain`, `translation_key`: the key. The most specific entry that matches wins.
/// - `role`: a reading or action a layout looks for (`KhalaHintRole`: the car's battery, its wake button, a boiler's
///   remaining-time sensor…).
/// - `section` (one name or a list): where a car control goes (`overview`, `climate`, `charging`, `more`).
/// - `glyph`: the tile glyph (`KhalaControl.Glyph` names: `chargePort`, `frunk`, `seat`…). A Khala glyph rather
///   than an SF Symbol name because it also orders the car's tiles.
/// - `timedOn`: `{service, field, unit?, domain?}` — the service that turns the entity on for a number of minutes
///   (a boiler's timer); `domain` defaults to the platform.
/// An entry with a role, section or glyph this build doesn't know keeps the parts it does know (`unknown` roles
/// match no reader; unknown sections and glyphs are dropped).
struct KhalaHint: Equatable {
    let platform: String
    let domain: String?
    let translationKey: String?
    let role: KhalaHintRole?
    let sections: [KhalaCarSection]
    let glyph: KhalaControl.Glyph?
    let timedOn: KhalaTimedOn?

    /// How much of the key is pinned: a translation key counts more than a domain.
    var specificity: Int {
        (translationKey == nil ? 0 : 2) + (domain == nil ? 0 : 1)
    }

    func matches(platform: String, domain: String, translationKey: String?) -> Bool {
        guard platform == self.platform else { return false }
        if let wanted = self.domain, wanted != domain { return false }
        if let wanted = self.translationKey, wanted != translationKey { return false }
        return true
    }
}

extension KhalaHint: Decodable {
    private enum CodingKeys: String, CodingKey {
        case platform, domain, role, section, glyph, timedOn
        case translationKey = "translation_key"
    }

    private enum TimedOnKeys: String, CodingKey {
        case domain, service, field, unit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platform = try container.decode(String.self, forKey: .platform)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)
        translationKey = try container.decodeIfPresent(String.self, forKey: .translationKey)
        role = (try? container.decodeIfPresent(String.self, forKey: .role)).flatMap { KhalaHintRole(rawValue: $0) ?? .unknown }
        let sectionNames: [String]
        if let list = try? container.decodeIfPresent([String].self, forKey: .section) {
            sectionNames = list
        } else if let one = try? container.decodeIfPresent(String.self, forKey: .section) {
            sectionNames = [one]
        } else {
            sectionNames = []
        }
        sections = sectionNames.map { KhalaCarSection(rawValue: $0) ?? .unknown }.filter { $0 != .unknown }
        glyph = (try? container.decodeIfPresent(String.self, forKey: .glyph)).flatMap(KhalaControl.Glyph.init)
        if container.contains(.timedOn) {
            let timed = try container.nestedContainer(keyedBy: TimedOnKeys.self, forKey: .timedOn)
            timedOn = KhalaTimedOn(
                domain: try timed.decodeIfPresent(String.self, forKey: .domain) ?? platform,
                service: try timed.decode(String.self, forKey: .service),
                field: try timed.decode(String.self, forKey: .field),
                unit: try timed.decodeIfPresent(String.self, forKey: .unit) ?? "min"
            )
        } else {
            timedOn = nil
        }
    }
}
