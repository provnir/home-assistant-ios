import Foundation

/// A row of the Settings screen's HOME ASSISTANT section: one entry of the frontend's own settings dashboard
/// (`configSections.dashboard`, `dashboard_2`, `dashboard_3` in home-assistant/frontend
/// `src/panels/config/config-sections.ts`), opened in the web UI at `path` under Khala's chrome.
struct KhalaServerSection: Hashable, Identifiable {
    /// The trailing figure a row shows, where it is cheap to know.
    enum Badge: Hashable {
        /// Number of automations.
        case automations
        /// Number of people.
        case people
        /// Pending updates and open repairs (the amber attention chip).
        case attention
    }

    let id: String
    let title: String
    let path: String
    let glyph: KhalaSettingsGlyph
    let requirement: KhalaServerRequirement
    let pages: [KhalaServerPage]
    let badge: Badge?
    let keywords: [String]

    init(
        id: String,
        title: String,
        path: String,
        glyph: KhalaSettingsGlyph,
        requirement: KhalaServerRequirement,
        pages: [KhalaServerPage] = [],
        badge: Badge? = nil,
        keywords: [String] = []
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.glyph = glyph
        self.requirement = requirement
        self.pages = pages
        self.badge = badge
        self.keywords = keywords
    }

    /// The section's tabs (pre-known sub-sections of its page).
    var tabs: [KhalaServerPage] { pages.filter(\.isTab) }
}
