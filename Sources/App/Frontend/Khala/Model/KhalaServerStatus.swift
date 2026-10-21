import Foundation

/// The figures the Settings screen shows next to its rows, read from the live states (cheap: no extra request)
/// plus the repairs list: pending updates (`update.*` entities that are on, as the frontend's updates summary
/// counts them), automations, people, and open repairs (nil when the server didn't answer, e.g. not an admin).
struct KhalaServerStatus: Hashable {
    var updates: Int
    var automations: Int
    var people: Int
    var repairs: Int?

    init(updates: Int = 0, automations: Int = 0, people: Int = 0, repairs: Int? = nil) {
        self.updates = updates
        self.automations = automations
        self.people = people
        self.repairs = repairs
    }

    init(entities: [KhalaEntity], repairs: Int?) {
        self.init(
            updates: entities.filter { $0.domain == "update" && $0.state == "on" }.count,
            automations: entities.filter { $0.domain == "automation" }.count,
            people: entities.filter { $0.domain == "person" }.count,
            repairs: repairs
        )
    }

    /// Open repairs in `repairs/list_issues`' answer (`{"issues": [{"ignored": Bool, ...}]}`): the ones not
    /// ignored, as the frontend's settings dashboard counts them. Nil for anything else.
    static func openRepairs(in json: Any?) -> Int? {
        guard let json = json as? [String: Any], let issues = json["issues"] as? [Any] else { return nil }
        return issues.filter { issue in
            KhalaValue.bool((issue as? [String: Any])?["ignored"]) != true
        }.count
    }

    /// The amber chip's words: "1 update", "2 repairs", "1 update · 2 repairs"; nil when nothing needs
    /// attention.
    var attentionText: String? {
        var parts: [String] = []
        if updates > 0 { parts.append(KhalaText.updates(updates)) }
        if let repairs, repairs > 0 { parts.append(KhalaText.repairs(repairs)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Where the server card leads: what needs attention first, else About.
    var attentionPath: String {
        if updates > 0 { return "/config/updates" }
        if let repairs, repairs > 0 { return "/config/repairs" }
        return "/config/info"
    }

    /// The trailing figure of a section row, if it has one.
    func figure(for badge: KhalaServerSection.Badge?) -> String? {
        switch badge {
        case .automations: return automations > 0 ? "\(automations)" : nil
        case .people: return people > 0 ? "\(people)" : nil
        case .attention, nil: return nil
        }
    }
}
