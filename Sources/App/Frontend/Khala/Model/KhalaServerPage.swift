import Foundation

/// One Home Assistant settings page under a section: a tab of the section's page (Devices & services →
/// Integrations · Devices · Entities · Helpers) or a page its navigation lists (System → Logs). Indexed by the
/// Settings search, and used to tell a section's own pages from the ones below them.
struct KhalaServerPage: Hashable {
    let title: String
    /// The frontend path, as the frontend's `configSections` names it.
    let path: String
    let glyph: KhalaSettingsGlyph
    let requirement: KhalaServerRequirement
    /// A tab of the section's page (pre-known, shown as Khala's bottom glass sub-tabs), as opposed to a page
    /// reached from the section's navigation list.
    let isTab: Bool
    /// More words the search matches.
    let keywords: [String]

    init(
        _ title: String,
        path: String,
        glyph: KhalaSettingsGlyph,
        requirement: KhalaServerRequirement = .core,
        isTab: Bool = false,
        keywords: [String] = []
    ) {
        self.title = title
        self.path = path
        self.glyph = glyph
        self.requirement = requirement
        self.isTab = isTab
        self.keywords = keywords
    }
}
