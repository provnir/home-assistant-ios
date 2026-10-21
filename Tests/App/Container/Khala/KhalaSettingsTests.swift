import Foundation
@testable import HomeAssistant
import Testing

/// Synthetic servers: a plain Home Assistant Container install, a Home Assistant OS one, a non-admin user.
private enum Servers {
    static let container = KhalaServerCapabilities(
        components: ["automation", "scene", "script", "blueprint", "zone", "lovelace", "person", "backup", "cloud"],
        isAdmin: true,
        version: "2026.10.2",
        locationName: "Home"
    )
    static let supervised = KhalaServerCapabilities(
        components: ["automation", "zone", "lovelace", "person", "hassio", "hardware", "mqtt"],
        isAdmin: true
    )
    static let guest = KhalaServerCapabilities(components: ["automation", "zone", "lovelace", "person"], isAdmin: false)
    static let loading = KhalaServerCapabilities()
}

struct KhalaSettingsCatalogTests {
    @Test func sectionsFollowTheFrontendsDashboardAndWhatTheServerHas() {
        let ids = KhalaSettingsCatalog.visibleSections(for: Servers.container).map(\.id)
        #expect(ids == [
            "cloud", "devices", "automations", "areas", "dashboards", "connectivity", "voice", "people", "system",
            "tools", "about",
        ])
        // Home Assistant OS: Apps, no Cloud.
        let supervised = KhalaSettingsCatalog.visibleSections(for: Servers.supervised).map(\.id)
        #expect(supervised.contains("apps"))
        #expect(!supervised.contains("cloud"))
        #expect(supervised.first == "devices")
    }

    @Test func noSupervisorMeansNoApps() {
        #expect(!KhalaSettingsCatalog.visibleSections(for: Servers.container).contains { $0.id == "apps" })
    }

    @Test func nonAdminsGetNoServerSections() {
        #expect(KhalaSettingsCatalog.visibleSections(for: Servers.guest).isEmpty)
    }

    @Test func untilTheServerAnswersOnlyCorePagesShow() {
        let ids = KhalaSettingsCatalog.visibleSections(for: Servers.loading).map(\.id)
        #expect(ids == ["devices", "automations", "connectivity", "voice", "system", "tools", "about"])
    }

    @Test func pagesAreFilteredToo() {
        let system = try! #require(KhalaSettingsCatalog.sections.first { $0.id == "system" })
        let titles = KhalaSettingsCatalog.visiblePages(of: system, for: Servers.container).map(\.title)
        #expect(titles.contains("Logs"))
        #expect(titles.contains("Backups"))
        #expect(!titles.contains("Storage"))
        #expect(!titles.contains("Hardware"))
        let os = KhalaSettingsCatalog.visiblePages(of: system, for: Servers.supervised).map(\.title)
        #expect(os.contains("Storage"))
        #expect(os.contains("Hardware"))
        #expect(!os.contains("Backups"))
    }

    @Test func pathsNormalizeTheRoutersDefaultPage() {
        #expect(KhalaSettingsCatalog.normalized("/config/integrations/dashboard") == "/config/integrations")
        #expect(KhalaSettingsCatalog.normalized("/config/dashboard?x=1") == "/config")
        #expect(KhalaSettingsCatalog.normalized("/config/entities/") == "/config/entities")
        #expect(KhalaSettingsCatalog.normalized("/dashboard") == "/dashboard")
        #expect(KhalaSettingsCatalog.isSettingsHome("/config"))
        #expect(KhalaSettingsCatalog.isSettingsHome("/config/dashboard"))
        #expect(!KhalaSettingsCatalog.isSettingsHome("/config/system"))
    }

    @Test func sectionRootsAreSectionPagesAndTheirTabs() {
        #expect(KhalaSettingsCatalog.isSectionRoot("/config/integrations/dashboard"))
        #expect(KhalaSettingsCatalog.isSectionRoot("/config/devices/dashboard"))
        #expect(KhalaSettingsCatalog.isSectionRoot("/config/helpers"))
        #expect(KhalaSettingsCatalog.isSectionRoot("/config/automation/dashboard"))
        #expect(KhalaSettingsCatalog.isSectionRoot("/config/voice-assistants/expose"))
        #expect(KhalaSettingsCatalog.isSectionRoot("/config/system"))
        // Below a section, and System's own pages, keep the frontend's back.
        #expect(!KhalaSettingsCatalog.isSectionRoot("/config/integrations/integration/met"))
        #expect(!KhalaSettingsCatalog.isSectionRoot("/config/automation/edit/123"))
        #expect(!KhalaSettingsCatalog.isSectionRoot("/config/logs"))
        #expect(!KhalaSettingsCatalog.isSectionRoot("/history"))
    }

    @Test func backReturnsToSettingsFromRootsAndFromWhereSettingsLanded() {
        #expect(KhalaSettingsCatalog.backLeadsToSettings(path: "/config/entities", entryPath: nil))
        #expect(KhalaSettingsCatalog.backLeadsToSettings(path: "/config/logs", entryPath: "/config/logs"))
        #expect(KhalaSettingsCatalog.backLeadsToSettings(path: "/config/tools/yaml", entryPath: "/config/tools/yaml"))
        #expect(!KhalaSettingsCatalog.backLeadsToSettings(path: "/config/logs", entryPath: nil))
        #expect(!KhalaSettingsCatalog.backLeadsToSettings(path: "/config/cloud/account", entryPath: "/config/cloud/start"))
    }

    @Test func landingFollowsTheFrontendsRedirect() {
        #expect(KhalaSettingsCatalog.isLanding("/config/tools/yaml", of: "/config/tools"))
        #expect(KhalaSettingsCatalog.isLanding("/config/integrations/dashboard", of: "/config/integrations"))
        #expect(!KhalaSettingsCatalog.isLanding("/lovelace/0", of: "/config/tools"))
        #expect(!KhalaSettingsCatalog.isLanding("/config/toolsy", of: "/config/tools"))
    }

    @Test func tabsNameTheirSection() {
        let devices = ["/config/integrations", "/config/devices", "/config/entities", "/config/helpers"]
        #expect(KhalaSettingsCatalog.section(forTabPaths: devices)?.title == "Devices & services")
        #expect(KhalaSettingsCatalog.section(forTabPaths: ["/config/person", "/config/users"])?.title == "People")
        #expect(KhalaSettingsCatalog.section(forTabPaths: ["/config/integrations", "/somewhere"]) == nil)
        #expect(KhalaSettingsCatalog.section(forTabPaths: []) == nil)
    }

    @Test func aPageBelongsToItsLongestMatchingSection() {
        #expect(KhalaSettingsCatalog.section(containing: "/config/integrations/integration/met")?.id == "devices")
        #expect(KhalaSettingsCatalog.section(containing: "/config/logs")?.id == "system")
        #expect(KhalaSettingsCatalog.section(containing: "/config/person")?.id == "people")
        #expect(KhalaSettingsCatalog.section(containing: "/history") == nil)
    }

    @Test func requirementsMirrorCanShowPage() {
        let core = KhalaServerRequirement.core
        let mqtt = KhalaServerRequirement.component("mqtt")
        let free = KhalaServerRequirement()
        #expect(core.isMet(by: Servers.loading))
        #expect(!mqtt.isMet(by: Servers.container))
        #expect(mqtt.isMet(by: Servers.supervised))
        #expect(free.isMet(by: Servers.container))
        #expect(!core.isMet(by: Servers.guest))
        #expect(KhalaServerRequirement(isCore: true, adminOnly: false).isMet(by: Servers.guest))
    }

    @Test func capabilitiesReadGetConfig() {
        let config: [String: Any] = [
            "components": ["hassio", "zone", 7],
            "version": "2026.11.0",
            "location_name": "Cabin",
        ]
        let read = KhalaServerCapabilities(isAdmin: true).merging(config: config)
        #expect(read.components == ["hassio", "zone"])
        #expect(read.hasSupervisor)
        #expect(read.version == "2026.11.0")
        #expect(read.locationName == "Cabin")
        #expect(read.isAdmin == true)
        #expect(KhalaServerCapabilities().merging(config: "nope") == KhalaServerCapabilities())
    }
}

struct KhalaSettingsSearchTests {
    private var entries: [KhalaSettingsEntry] {
        KhalaSettingsCatalog.searchEntries(for: Servers.container) + [
            KhalaSettingsEntry(
                id: "app:notifications", title: "Notifications", subtitle: KhalaText.thisApp, glyph: .notifications,
                keywords: ["push", "alerts"], target: .app(id: "notifications")
            ),
            KhalaSettingsEntry(
                id: "app:general", title: "General", subtitle: KhalaText.thisApp, glyph: .appGeneral,
                keywords: ["theme"], target: .app(id: "general")
            ),
        ]
    }

    @Test func emptyQueryFindsNothing() {
        #expect(KhalaSettingsSearch.results(for: "  ", in: entries).isEmpty)
    }

    @Test func titlePrefixesComeFirst() {
        let titles = KhalaSettingsSearch.results(for: "auto", in: entries).map(\.title)
        #expect(titles.first == "Automations & scenes")
        // The Automations tab opens the same page as its section: listed once.
        #expect(!titles.contains("Automations"))
    }

    @Test func pagesBelowSectionsAreFound() {
        let logs = KhalaSettingsSearch.results(for: "logs", in: entries)
        #expect(logs.first?.target == .serverPage(path: "/config/logs"))
        #expect(logs.first?.subtitle == "System")
    }

    @Test func appAndServerSettingsMix() {
        let results = KhalaSettingsSearch.results(for: "general", in: entries)
        #expect(results.first?.target == .app(id: "general"))
        let alerts = KhalaSettingsSearch.results(for: "alerts", in: entries)
        #expect(alerts.map(\.target) == [.app(id: "notifications")])
    }

    @Test func matchingIgnoresCaseAndDiacritics() {
        #expect(KhalaSettingsSearch.results(for: "ZÖNES", in: entries).first?.title == "Zones")
        #expect(KhalaSettingsSearch.results(for: "nabu", in: entries).first?.title == "Home Assistant Cloud")
    }

    @Test func wordStartsBeatInnerMatches() {
        let entry = { (title: String) in
            KhalaSettingsEntry(id: title, title: title, subtitle: nil, glyph: .page, keywords: [], target: .app(id: title))
        }
        let results = KhalaSettingsSearch.results(for: "set", in: [entry("Reset"), entry("Quick settings")])
        #expect(results.map(\.title) == ["Quick settings", "Reset"])
    }

    @Test func pagesTheServerLacksAreNotIndexed() {
        #expect(KhalaSettingsSearch.results(for: "hardware", in: entries).isEmpty)
        #expect(KhalaSettingsSearch.results(for: "apps", in: entries).isEmpty)
    }
}

struct KhalaServerStatusTests {
    private func entity(_ id: String, _ state: String) -> KhalaEntity {
        KhalaEntity(entityId: id, state: state, lastChanged: Date(timeIntervalSince1970: 0), attributes: [:])
    }

    @Test func figuresComeFromTheLiveStates() {
        let status = KhalaServerStatus(entities: [
            entity("update.core", "on"),
            entity("update.os", "off"),
            entity("automation.a", "on"),
            entity("automation.b", "off"),
            entity("person.sam", "home"),
        ], repairs: nil)
        #expect(status.updates == 1)
        #expect(status.automations == 2)
        #expect(status.people == 1)
        #expect(status.attentionText == "1 update")
        #expect(status.attentionPath == "/config/updates")
        #expect(status.figure(for: .automations) == "2")
        #expect(status.figure(for: .people) == "1")
        #expect(status.figure(for: .attention) == nil)
        #expect(status.figure(for: nil) == nil)
    }

    @Test func repairsJoinTheAttentionChip() {
        #expect(KhalaServerStatus(updates: 2, repairs: 3).attentionText == "2 updates · 3 repairs")
        #expect(KhalaServerStatus(repairs: 1).attentionText == "1 repair")
        #expect(KhalaServerStatus(repairs: 1).attentionPath == "/config/repairs")
        #expect(KhalaServerStatus().attentionText == nil)
        #expect(KhalaServerStatus().attentionPath == "/config/info")
    }

    @Test func openRepairsSkipIgnoredOnes() {
        let answer: [String: Any] = ["issues": [
            ["issue_id": "a", "ignored": NSNumber(value: false)],
            ["issue_id": "b", "ignored": NSNumber(value: true)],
            ["issue_id": "c"],
        ]]
        #expect(KhalaServerStatus.openRepairs(in: answer) == 2)
        #expect(KhalaServerStatus.openRepairs(in: ["issues": []]) == 0)
        #expect(KhalaServerStatus.openRepairs(in: "denied") == nil)
    }
}

struct KhalaPageHeaderTests {
    /// A tabbed settings page as `KhalaFrontendScript` posts it (WebKit's shapes: NSNumber, NSNull).
    static let devicesPage: [String: Any] = [
        "path": "/config/devices/dashboard",
        "dialog": NSNull(),
        "dashboard": NSNull(),
        "actions": [Any](),
        "pageBack": NSNumber(value: true),
        "page": [
            "kind": "tabs",
            "lifted": NSNumber(value: true),
            "title": "Devices",
            "back": NSNumber(value: true),
            "tabs": [
                ["path": "/config/integrations", "title": "Integrations", "active": NSNumber(value: false)],
                ["path": "/config/devices", "title": "Devices", "active": NSNumber(value: true)],
                ["path": "/config/entities", "title": "Entities", "active": NSNumber(value: false)],
                ["path": "/config/helpers", "title": "Helpers", "active": NSNumber(value: false)],
            ],
            "search": ["placeholder": "Search 5 devices", "value": ""],
            "primary": ["id": "p5", "title": "Add device", "key": NSNull()],
            "tools": [
                ["id": "p2", "title": "Menu", "key": NSNull(), "children": [
                    ["id": "p0", "title": "Show ignored", "key": "show-ignored", "checked": NSNumber(value: false)],
                    ["id": "p1", "title": "Show disabled", "key": "show-disabled", "checked": NSNumber(value: true)],
                ]],
                ["id": "p4", "title": "Help", "key": NSNull()],
            ],
            "titleMenu": [Any](),
        ] as [String: Any],
    ]

    private func header(
        _ json: [String: Any] = devicesPage,
        path: String? = nil,
        moreInfo: Bool = false,
        entry: String? = nil
    ) -> KhalaPageHeader? {
        let state = KhalaFrontendState(json: json)
        return KhalaPageHeader(
            path: path ?? state?.path,
            state: state,
            isMoreInfoOpen: moreInfo,
            settingsEntryPath: entry,
            fallbackTitle: "Settings"
        )
    }

    private func page(_ changes: [String: Any], path: String = "/config/logs", dialog: String? = nil) -> [String: Any] {
        var page = Self.devicesPage["page"] as! [String: Any]
        page["tabs"] = [Any]()
        page["search"] = NSNull()
        page["kind"] = "subpage"
        for (key, value) in changes { page[key] = value }
        var json = Self.devicesPage
        json["path"] = path
        json["page"] = page
        json["dialog"] = dialog.map { $0 as Any } ?? NSNull()
        return json
    }

    @Test func theScriptsPageReportParses() throws {
        let state = try #require(KhalaFrontendState(json: Self.devicesPage))
        let page = try #require(state.page)
        #expect(page.kind == .tabs)
        #expect(page.isLifted)
        #expect(page.hasBack)
        #expect(page.tabs.count == 4)
        #expect(page.tabs[1] == KhalaPageTab(path: "/config/devices", title: "Devices", isActive: true))
        #expect(page.search == KhalaPageSearch(placeholder: "Search 5 devices"))
        #expect(page.primary?.title == "Add device")
        #expect(page.tools.first?.children.last?.isChecked == true)
        #expect(page.tools.last?.isChecked == nil)
        #expect(state.dashboard == nil)
    }

    @Test func aTabbedSettingsPageIsTitledBySectionAndBacksToSettings() throws {
        let header = try #require(self.header())
        #expect(header.title == "Devices & services")
        #expect(header.back == .settings)
        #expect(header.showsTitle)
        #expect(header.tabs.map(\.title) == ["Integrations", "Devices", "Entities", "Helpers"])
        #expect(header.activeTabIndex == 1)
        #expect(header.search?.placeholder == "Search 5 devices")
        #expect(header.primary?.id == "p5")
        #expect(header.toolSections.map { $0.map(\.title) } == [["Show ignored", "Show disabled"], ["Help"]])
        #expect(header.height == 62 + 48 + 59)
    }

    @Test func aDialogLeavesOnlyTheRow() throws {
        var json = Self.devicesPage
        json["dialog"] = "ha-more-info-dialog"
        let header = try #require(self.header(json))
        #expect(header.back == .frontend)
        #expect(!header.showsTitle)
        #expect(header.search == nil)
        #expect(header.tabs.isEmpty)
        #expect(header.primary == nil)
        #expect(header.toolSections.isEmpty)
        #expect(header.height == 62)
        #expect(try #require(self.header(moreInfo: true)).height == 62)
    }

    @Test func belowASectionTheFrontendGoesBack() throws {
        let header = try #require(self.header(page(["title": "Met.no"]), path: "/config/integrations/integration/met"))
        #expect(header.back == .frontend)
        #expect(header.title == "Met.no")
        #expect(header.height == 62 + 48)
    }

    @Test func thePageSettingsOpenedBacksToSettings() throws {
        let json = page(["title": "Logs"], path: "/config/logs")
        #expect(try #require(header(json)).back == .frontend)
        #expect(try #require(header(json, entry: "/config/logs")).back == .settings)
    }

    @Test func aTopLevelPageKeepsTheMenuButton() throws {
        let json = page(["kind": "appbar", "title": "History", "back": NSNumber(value: false)], path: "/history")
        let header = try #require(self.header(json))
        #expect(header.back == .none)
        #expect(header.title == "History")
    }

    @Test func titleFallsBackToTheActiveTabThenToTheCallersWord() throws {
        let tabs: [[String: Any]] = [
            ["path": "/config/voice-assistants/assistants", "title": "Assistants", "active": NSNumber(value: true)],
            ["path": "/somewhere/else", "title": "Else", "active": NSNumber(value: false)],
        ]
        let titled = try #require(header(page(["kind": "tabs", "tabs": tabs, "title": NSNull()], path: "/x/y")))
        #expect(titled.title == "Assistants")
        let bare = try #require(header(page(["title": NSNull()], path: "/x/y")))
        #expect(bare.title == "Settings")
    }

    @Test func oneTabIsJustThePage() throws {
        let tabs: [[String: Any]] = [["path": "/config/tags", "title": "Tags", "active": NSNumber(value: true)]]
        let header = try #require(self.header(page(["kind": "tabs", "tabs": tabs, "title": "Tags"], path: "/config/tags")))
        #expect(header.tabs.isEmpty)
    }

    @Test func noLiftNoPageHeader() {
        #expect(header(page(["lifted": NSNumber(value: false)])) == nil)
        var json = Self.devicesPage
        json["page"] = NSNull()
        #expect(header(json) == nil)
        // A report about another panel than the one on screen (it trails a navigation) doesn't count.
        #expect(header(path: "/lovelace/0") == nil)
    }

    @Test func toolSectionsKeepButtonRunsTogether() {
        let button = { (id: String) in KhalaFrontendAction(id: id, title: id) }
        let menu = KhalaFrontendAction(id: "m", title: "Menu", children: [button("x"), button("y")])
        let sections = KhalaPageHeader.sections(of: [button("a"), button("b"), menu, button("c")])
        #expect(sections.map { $0.map(\.id) } == [["a", "b"], ["x", "y"], ["c"]])
        #expect(KhalaPageHeader.sections(of: []).isEmpty)
    }

    @Test func tabGlyphsComeFromTheCatalog() {
        #expect(KhalaPageTab(path: "/config/integrations", title: "", isActive: false).glyph == .integrations)
        #expect(KhalaPageTab(path: "/config/helpers", title: "", isActive: false).glyph == .helpers)
        #expect(KhalaPageTab(path: "/somewhere", title: "", isActive: false).glyph == .page)
    }

    @Test func scriptCallsEscapeTheirArguments() {
        let search = KhalaFrontendScript.searchCall("a \"b\"\n")
        #expect(search == #"window.__khala ? window.__khala.search("a \"b\"\n") : false"#)
        // JSON may escape the slashes ("\/"), which a JavaScript string reads back as "/".
        let tab = KhalaFrontendScript.tabCall(path: "/config/devices").replacingOccurrences(of: "\\/", with: "/")
        #expect(tab == #"window.__khala ? window.__khala.tab("/config/devices") : false"#)
        let source = KhalaFrontendScript.source()
        #expect(source.contains("const TITLE_BLOCK = 48;"))
        #expect(source.contains("const SEARCH_BLOCK = 59;"))
        #expect(source.contains("const TAB_BAR = 78;"))
        #expect(source.contains("search,"))
        #expect(!source.contains("\\#("))
    }
}

struct KhalaSettingsDestinationTests {
    @Test func settingsIsADestinationOutsideTheMenuList() {
        #expect(KhalaDestination.settings.menuHighlight == .settings)
        #expect(!KhalaDestination.allCases.contains(.settings))
        #expect(KhalaDestination.settings.title == "Settings")
    }

    @Test func versionCopy() {
        #expect(KhalaText.serverSubtitle(version: "2026.10.2", host: "ha.local") == "Home Assistant 2026.10.2 · ha.local")
        #expect(KhalaText.serverSubtitle(version: nil, host: nil) == "Home Assistant")
        #expect(KhalaText.appVersion("2026.10.2", build: "17.1") == "Khala 2026.10.2 (17.1)")
        #expect(KhalaText.appVersion(nil, build: "3") == "Khala")
    }
}
