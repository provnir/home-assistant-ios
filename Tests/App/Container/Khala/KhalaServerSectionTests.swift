import Foundation
@testable import HomeAssistant
import Testing

/// `KhalaServerSection` / `KhalaServerPage`: the Settings screen's server rows and the pages under them.
struct KhalaServerSectionTests {
    private static let glyph = KhalaSettingsCatalog.sections[0].glyph

    @Test func aPageDefaultsToACoreNonTabPage() {
        let page = KhalaServerPage("Logs", path: "/config/logs", glyph: Self.glyph)
        #expect(page.requirement == .core)
        #expect(!page.isTab)
        #expect(page.keywords.isEmpty)
    }

    @Test func aSectionsTabsAreOnlyItsTabPagesInOrder() {
        let section = KhalaServerSection(
            id: "x",
            title: "X",
            path: "/config/x",
            glyph: Self.glyph,
            requirement: .core,
            pages: [
                KhalaServerPage("B", path: "/config/x/b", glyph: Self.glyph, isTab: true),
                KhalaServerPage("Log", path: "/config/x/log", glyph: Self.glyph),
                KhalaServerPage("A", path: "/config/x/a", glyph: Self.glyph, isTab: true),
            ]
        )
        #expect(section.tabs.map(\.title) == ["B", "A"])
        #expect(section.badge == nil)
        #expect(section.keywords.isEmpty)
        let bare = KhalaServerSection(id: "y", title: "Y", path: "/config/y", glyph: Self.glyph, requirement: .core)
        #expect(bare.pages.isEmpty)
        #expect(bare.tabs.isEmpty)
    }

    @Test func sectionsAndPagesAreValues() {
        let page = KhalaServerPage("Logs", path: "/config/logs", glyph: Self.glyph)
        #expect(page == KhalaServerPage("Logs", path: "/config/logs", glyph: Self.glyph))
        #expect(page != KhalaServerPage("Logs", path: "/config/logs", glyph: Self.glyph, isTab: true))
        #expect(Set([page, page]).count == 1)
    }

    @Test func theCatalogHasUniqueIdsAndPaths() {
        let sections = KhalaSettingsCatalog.sections
        #expect(Set(sections.map(\.id)).count == sections.count)
        #expect(Set(sections.map(\.path)).count == sections.count)
        for section in sections {
            #expect(section.path.hasPrefix("/config"), "\(section.id)")
            #expect(Set(section.pages.map(\.path)).count == section.pages.count, "\(section.id)")
            for page in section.pages {
                // Most pages sit under /config; integration panels (e.g. /knx) sit at the root.
                #expect(page.path.hasPrefix("/"), "\(section.id) \(page.path)")
                #expect(!page.title.isEmpty)
            }
        }
    }
}
