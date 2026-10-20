import Foundation
@testable import HomeAssistant
import Testing

struct KhalaFrontendPathTests {
    private let dashboards = [
        KhalaDashboard(id: "home", title: "Overview"),
        KhalaDashboard(id: "dashboard-den", title: "Den"),
        KhalaDashboard(id: "energy", title: "Energy"),
    ]

    @Test func segmentsDropQueryFragmentAndEmptyParts() {
        #expect(KhalaFrontendPath.segments("/lovelace/kitchen?edit=1") == ["lovelace", "kitchen"])
        #expect(KhalaFrontendPath.segments("//config/automation/#x") == ["config", "automation"])
        #expect(KhalaFrontendPath.segments("/dashboard-den/living%20room") == ["dashboard-den", "living room"])
        #expect(KhalaFrontendPath.segments("/").isEmpty)
    }

    @Test func dashboardOfAPathIsItsFirstSegment() {
        #expect(KhalaFrontendPath.dashboard(for: "/dashboard-den/lights", in: dashboards)?.title == "Den")
        #expect(KhalaFrontendPath.dashboard(for: "/energy", in: dashboards)?.id == "energy")
        #expect(KhalaFrontendPath.dashboard(for: "/config/automation/dashboard", in: dashboards) == nil)
        #expect(KhalaFrontendPath.dashboard(for: nil, in: dashboards) == nil)
    }

    @Test func rootBelongsToTheDefaultDashboard() {
        #expect(KhalaFrontendPath.dashboard(for: "/", in: dashboards)?.id == "home")
        #expect(KhalaFrontendPath.dashboard(for: "/", in: []) == nil)
    }

    @Test func viewPathUsesThePathOrTheIndex() {
        let named = KhalaDashboardView(index: 2, path: "lights", title: "Lights", icon: nil)
        let unnamed = KhalaDashboardView(index: 3, path: nil, title: nil, icon: nil)
        let spaced = KhalaDashboardView(index: 0, path: "living room", title: nil, icon: nil)
        #expect(KhalaFrontendPath.viewPath(prefix: "/dashboard-den", view: named) == "/dashboard-den/lights")
        #expect(KhalaFrontendPath.viewPath(prefix: "/dashboard-den/", view: unnamed) == "/dashboard-den/3")
        #expect(KhalaFrontendPath.viewPath(prefix: "/lovelace", view: spaced) == "/lovelace/living%20room")
    }

    @Test func dashboardSearchMatchesTitles() {
        #expect(KhalaDashboard.matching("en", in: dashboards).map(\.id) == ["dashboard-den", "energy"])
        #expect(KhalaDashboard.matching("  ", in: dashboards).count == 3)
        #expect(KhalaDashboard(id: "map", title: "Map").path == "/map")
    }
}

struct KhalaFrontendStateTests {
    /// The shape `KhalaFrontendScript` posts (as WebKit hands it over: numbers as NSNumber, null as NSNull).
    static let report: [String: Any] = [
        "path": "/dashboard-den/lights",
        "dialog": NSNull(),
        "dashboard": [
            "prefix": "/dashboard-den",
            "views": [
                ["index": NSNumber(value: 0), "path": "main", "title": "Main", "icon": "mdi:home"],
                ["index": NSNumber(value: 1), "path": "lights", "title": NSNull(), "icon": NSNull()],
                ["index": NSNumber(value: 3), "path": NSNull(), "title": "Garden", "icon": NSNull()],
                ["path": "broken"],
            ],
            "current": NSNumber(value: 1),
            "subview": NSNumber(value: false),
            "subviewTitle": NSNull(),
            "backButton": NSNumber(value: false),
            "editMode": NSNumber(value: false),
            "unnamedTitle": "Unnamed view",
            "headerHidden": NSNumber(value: true),
        ] as [String: Any],
        "actions": [
            ["id": "a0", "title": "Search Home Assistant", "key": "ui.panel.lovelace.menu.search_home_assistant"],
            [
                "id": "g3", "title": "Add", "key": NSNull(),
                "children": [["id": "a1", "title": "Add device", "key": "ui.panel.lovelace.menu.add_device"]],
            ] as [String: Any],
            ["title": "no id"],
        ],
        "pageBack": NSNull(),
    ]

    @Test func readsTheScriptsReport() throws {
        let state = try #require(KhalaFrontendState(json: Self.report))
        #expect(state.path == "/dashboard-den/lights")
        #expect(state.dialog == nil)
        let page = try #require(state.dashboard)
        #expect(page.prefix == "/dashboard-den")
        #expect(page.panelId == "dashboard-den")
        #expect(page.views.map(\.index) == [0, 1, 3])
        #expect(page.views[1].title == nil)
        #expect(page.views[2].path == nil)
        #expect(page.currentViewIndex == 1)
        #expect(page.isHeaderHidden)
        #expect(!page.isEditMode)
        #expect(page.unnamedViewTitle == "Unnamed view")
        #expect(state.actions.map(\.id) == ["a0", "g3"])
        #expect(state.actions[1].children.map(\.title) == ["Add device"])
        #expect(state.pageBack == nil)
        #expect(KhalaFrontendState(json: ["path": "/config/automation", "pageBack": NSNumber(value: true)])?.pageBack == true)
    }

    @Test func malformedReportsReadAsNil() {
        #expect(KhalaFrontendState(json: nil) == nil)
        #expect(KhalaFrontendState(json: ["dialog": "x"]) == nil)
        #expect(KhalaFrontendState(json: ["path": "/x", "dashboard": ["views": []]])?.dashboard == nil)
    }

    @Test func actionGlyphsFollowTheFrontendsKeys() {
        let glyph = { (key: String?) in KhalaFrontendAction(id: "a", title: "t", key: key).glyph }
        #expect(glyph("ui.panel.lovelace.menu.search_home_assistant") == .search)
        #expect(glyph("ui.panel.lovelace.menu.assist_tooltip") == .assist)
        #expect(glyph("ui.panel.lovelace.menu.add") == .add)
        #expect(glyph("ui.panel.lovelace.menu.add_device") == .device)
        #expect(glyph("ui.panel.lovelace.menu.create_automation") == .automation)
        #expect(glyph("ui.panel.lovelace.menu.configure_ui") == .edit)
        #expect(glyph("ui.panel.lovelace.menu.edit_overview") == .edit)
        #expect(glyph("ui.common.refresh") == .refresh)
        #expect(glyph("ui.panel.lovelace.unused_entities.title") == .list)
        #expect(glyph("something.else") == nil)
        #expect(glyph(nil) == nil)
    }
}

struct KhalaDashboardHeaderTests {
    private let dashboards = [
        KhalaDashboard(id: "home", title: "Overview"),
        KhalaDashboard(id: "dashboard-den", title: "Den"),
    ]

    private func header(
        path: String? = "/dashboard-den/lights",
        state: KhalaFrontendState? = KhalaFrontendState(json: KhalaFrontendStateTests.report),
        moreInfo: Bool = false,
        dashboards: [KhalaDashboard]? = nil
    ) -> KhalaDashboardHeader {
        KhalaDashboardHeader(
            dashboards: dashboards ?? self.dashboards,
            path: path,
            state: state,
            isMoreInfoOpen: moreInfo,
            fallbackTitle: "Dashboards"
        )
    }

    private func page(
        prefix: String = "/dashboard-den",
        views: Int = 2,
        current: Int? = 0,
        subview: Bool = false,
        subviewTitle: String? = nil,
        backButton: Bool = false,
        editMode: Bool = false,
        headerHidden: Bool = true
    ) -> KhalaDashboardPage {
        KhalaDashboardPage(
            prefix: prefix,
            views: (0 ..< views).map { KhalaDashboardView(index: $0, path: "v\($0)", title: "View \($0)", icon: nil) },
            currentViewIndex: current,
            isSubview: subview,
            subviewTitle: subviewTitle,
            hasBackButton: backButton,
            isEditMode: editMode,
            isHeaderHidden: headerHidden
        )
    }

    @Test func dashboardNameViewsAndCurrentView() {
        let header = header()
        #expect(header.current?.id == "dashboard-den")
        #expect(header.title == "Den")
        #expect(header.views.map(\.title) == ["Main", "Unnamed view", "Garden"])
        #expect(header.views.map(\.isCurrent) == [false, true, false])
        #expect(header.subtitle == "Unnamed view")
        #expect(header.viewPrefix == "/dashboard-den")
        #expect(!header.showsBack)
        #expect(header.actions.count == 2)
        #expect(header.dashboards.map(\.id) == ["home", "dashboard-den"])
    }

    @Test func oneViewMeansNoViewChoice() {
        let header = header(state: KhalaFrontendState(path: "/dashboard-den/v0", dashboard: page(views: 1)))
        #expect(header.views.isEmpty)
        #expect(header.viewPrefix == nil)
        #expect(header.subtitle == nil)
    }

    @Test func subviewShowsBackAndItsTitle() {
        let state = KhalaFrontendState(
            path: "/dashboard-den/detail",
            dashboard: page(current: 5, subview: true, subviewTitle: "Detail")
        )
        let header = header(state: state)
        #expect(header.showsBack)
        #expect(header.subtitle == "Detail")
        #expect(header.views.allSatisfy { !$0.isCurrent })
    }

    @Test func pageBackButtonShowsBack() {
        #expect(header(state: KhalaFrontendState(path: "/dashboard-den/v0", dashboard: page(backButton: true))).showsBack)
    }

    @Test func dialogsShowBack() {
        let plain = KhalaFrontendState(path: "/dashboard-den/v0", dashboard: page())
        #expect(!header(state: plain).showsBack)
        #expect(header(state: plain, moreInfo: true).showsBack)
        let dialog = KhalaFrontendState(path: "/dashboard-den/v0", dialog: "ha-more-info-dialog", dashboard: page())
        #expect(header(state: dialog).showsBack)
    }

    @Test func pagesOffTheDashboardsShowBackAndTheFallbackTitle() {
        let header = header(path: "/config/automation/dashboard", state: nil)
        #expect(header.current == nil)
        #expect(header.title == "Dashboards")
        #expect(header.showsBack)
        #expect(header.views.isEmpty)
        #expect(header.actions.isEmpty)
    }

    private let settings = KhalaDashboard(id: "config", title: "Home Assistant settings")

    private func settingsHeader(path: String, pageBack: Bool?) -> KhalaDashboardHeader {
        KhalaDashboardHeader(
            dashboards: dashboards,
            otherPages: [settings],
            path: path,
            state: pageBack.map { KhalaFrontendState(path: path, pageBack: $0) },
            isMoreInfoOpen: false,
            fallbackTitle: "Dashboards"
        )
    }

    @Test func serverSettingsRootKeepsTheMenuButton() {
        let header = settingsHeader(path: "/config/dashboard", pageBack: false)
        #expect(header.title == "Home Assistant settings")
        #expect(header.current == nil)
        #expect(header.currentPage == settings)
        #expect(!header.showsBack)
        #expect(header.dashboards.map(\.id) == ["home", "dashboard-den"])
    }

    @Test func serverSettingsSubPagesShowBackInItsPlace() {
        let header = settingsHeader(path: "/config/automation/dashboard", pageBack: true)
        #expect(header.title == "Home Assistant settings")
        #expect(header.showsBack)
    }

    @Test func withoutTheScriptAListedPageIsARootAndAnUnlistedOneOffersBack() {
        #expect(!settingsHeader(path: "/config/dashboard", pageBack: nil).showsBack)
        #expect(settingsHeader(path: "/profile/general", pageBack: nil).showsBack)
        #expect(!settingsHeader(path: "/profile/general", pageBack: false).showsBack)
    }

    @Test func nothingIsOffADashboardBeforeTheListLoads() {
        #expect(!header(path: "/config", state: nil, dashboards: []).showsBack)
    }

    @Test func aReportAboutAnotherDashboardIsIgnored() {
        // The script reports a moment after the URL moved on.
        let stale = KhalaFrontendState(json: KhalaFrontendStateTests.report)
        let header = header(path: "/home/overview", state: stale.map {
            KhalaFrontendState(path: "/home/overview", dialog: nil, dashboard: $0.dashboard, actions: $0.actions)
        })
        #expect(header.title == "Overview")
        #expect(header.views.isEmpty)
        #expect(header.actions.isEmpty)
    }

    @Test func theScriptsPathWinsOverTheURLObservation() {
        let header = header(path: "/home/overview")
        #expect(header.title == "Den")
    }

    @Test func aVisibleFrontendHeaderKeepsItsOwnViewsAndActions() {
        let state = KhalaFrontendState(
            path: "/dashboard-den/v0",
            dashboard: page(headerHidden: false),
            actions: [KhalaFrontendAction(id: "a0", title: "Search")]
        )
        let header = header(state: state)
        #expect(header.views.isEmpty)
        #expect(header.actions.isEmpty)
        #expect(header.title == "Den")
    }

    @Test func editModeLeavesTheEditToolbarAlone() {
        let state = KhalaFrontendState(path: "/dashboard-den/v0", dashboard: page(editMode: true))
        #expect(header(state: state).views.isEmpty)
    }

    @Test func untitledViewsFallBackToANumberedName() {
        let state = KhalaFrontendState(
            path: "/dashboard-den/0",
            dashboard: KhalaDashboardPage(
                prefix: "/dashboard-den",
                views: [
                    KhalaDashboardView(index: 0, path: nil, title: nil, icon: nil),
                    KhalaDashboardView(index: 1, path: nil, title: nil, icon: nil),
                ],
                currentViewIndex: 0
            )
        )
        #expect(header(state: state).views.map(\.title) == ["View 1", "View 2"])
    }
}

struct KhalaFrontendScriptTests {
    @Test func scriptTalksToTheBridgeAndReservesTheHeader() {
        let source = KhalaFrontendScript.source(headerInset: 62)
        #expect(source.contains("const HANDLER = \"khalaShell\";"))
        #expect(source.contains("const INSET = 62;"))
        #expect(source.contains("--app-safe-area-inset-top"))
        #expect(source.contains("window.__khala = Object.freeze"))
        #expect(!source.contains("\\#("))
        #expect(KhalaFrontendScript.headerInset == 62)
    }

    @Test func performCallEscapesItsArguments() {
        let call = KhalaFrontendScript.performCall(actionId: "a1", title: "Say \"hi\"\n</script>")
        #expect(call.hasPrefix(#"window.__khala ? window.__khala.perform("a1", "Say \"hi\"\n"#))
        #expect(call.hasSuffix(") : false"))
        #expect(!call.contains("\n"))
    }
}
