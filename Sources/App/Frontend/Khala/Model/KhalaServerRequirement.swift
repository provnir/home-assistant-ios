import Foundation

/// When a Home Assistant settings page exists on a server. Mirrors the frontend's own rule for its settings
/// navigation (home-assistant/frontend 20260930.4, `src/common/config/can_show_page.ts` and
/// `filter_navigation_pages.ts`): a core page always shows, any other one when one of its integrations is
/// loaded (or when it names none), and admin-only pages never show to other users. Khala adds one rule of its
/// own: Apps (add-ons) needs the Supervisor — the frontend still lists an "about apps" page without it.
struct KhalaServerRequirement: Hashable {
    var isCore: Bool
    var components: [String]
    var needsSupervisor: Bool
    var adminOnly: Bool

    init(isCore: Bool = false, components: [String] = [], needsSupervisor: Bool = false, adminOnly: Bool = true) {
        self.isCore = isCore
        self.components = components
        self.needsSupervisor = needsSupervisor
        self.adminOnly = adminOnly
    }

    static let core = KhalaServerRequirement(isCore: true)

    static func component(_ names: String...) -> KhalaServerRequirement {
        KhalaServerRequirement(components: names)
    }

    func isMet(by server: KhalaServerCapabilities) -> Bool {
        if adminOnly, server.isAdmin == false { return false }
        if needsSupervisor, !server.hasSupervisor { return false }
        if isCore || components.isEmpty { return true }
        return components.contains { server.hasLoaded($0) }
    }
}
