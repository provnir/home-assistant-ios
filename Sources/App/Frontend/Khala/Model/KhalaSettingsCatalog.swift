import Foundation

/// Home Assistant's settings as the Settings screen offers them: the frontend's own settings dashboard
/// (home-assistant/frontend 20260930.4, `src/panels/config/config-sections.ts`: `dashboard`, `dashboard_2`,
/// `dashboard_3`, with Home Assistant Cloud first as `ha-config-dashboard.ts` `_pages` adds it) in the same
/// order, each with the pages under it (its tabs, or the pages its navigation lists), filtered by what the
/// server has (`KhalaServerRequirement`). The companion-app entry (`#external-app-configuration`) is left out:
/// the app's own settings are the screen's THIS APP section. Titles are the frontend's English ones.
enum KhalaSettingsCatalog {
    static let sections: [KhalaServerSection] = [
        KhalaServerSection(
            id: "cloud", title: "Home Assistant Cloud", path: "/config/cloud", glyph: .cloud,
            requirement: .component("cloud"), keywords: ["Nabu Casa", "remote"]
        ),
        KhalaServerSection(
            id: "devices", title: "Devices & services", path: "/config/integrations", glyph: .devices,
            requirement: .core,
            pages: [
                KhalaServerPage("Integrations", path: "/config/integrations", glyph: .integrations, isTab: true),
                KhalaServerPage("Devices", path: "/config/devices", glyph: .devices, isTab: true),
                KhalaServerPage("Entities", path: "/config/entities", glyph: .entities, isTab: true),
                KhalaServerPage("Helpers", path: "/config/helpers", glyph: .helpers, isTab: true),
            ]
        ),
        KhalaServerSection(
            id: "automations", title: "Automations & scenes", path: "/config/automation", glyph: .automations,
            requirement: .core,
            pages: [
                KhalaServerPage(
                    "Automations", path: "/config/automation", glyph: .automations,
                    requirement: .component("automation"), isTab: true
                ),
                KhalaServerPage(
                    "Scenes", path: "/config/scene", glyph: .scenes, requirement: .component("scene"), isTab: true
                ),
                KhalaServerPage(
                    "Scripts", path: "/config/script", glyph: .scripts, requirement: .component("script"), isTab: true
                ),
                KhalaServerPage(
                    "Blueprints", path: "/config/blueprint", glyph: .blueprints,
                    requirement: .component("blueprint"), isTab: true
                ),
            ],
            badge: .automations
        ),
        KhalaServerSection(
            id: "areas", title: "Areas, labels & zones", path: "/config/areas", glyph: .areas,
            requirement: .component("zone"),
            pages: [
                KhalaServerPage("Areas", path: "/config/areas", glyph: .areas, isTab: true),
                KhalaServerPage("Labels", path: "/config/labels", glyph: .labels, isTab: true),
                KhalaServerPage("Zones", path: "/config/zone", glyph: .zones, requirement: .component("zone"), isTab: true),
            ],
            keywords: ["Floors", "Rooms"]
        ),
        KhalaServerSection(
            id: "apps", title: "Apps", path: "/config/apps", glyph: .apps,
            requirement: KhalaServerRequirement(isCore: true, needsSupervisor: true), keywords: ["Add-ons", "Supervisor"]
        ),
        KhalaServerSection(
            id: "dashboards", title: "Dashboards", path: "/config/lovelace/dashboards", glyph: .dashboards,
            requirement: .component("lovelace")
        ),
        KhalaServerSection(
            id: "connectivity", title: "Connectivity", path: "/config/connectivity", glyph: .connectivity,
            requirement: .core,
            pages: [
                KhalaServerPage("Matter", path: "/config/matter", glyph: .radio, requirement: .component("matter")),
                KhalaServerPage("Zigbee", path: "/config/zha", glyph: .radio, requirement: .component("zha")),
                KhalaServerPage("Z-Wave", path: "/config/zwave_js", glyph: .radio, requirement: .component("zwave_js")),
                KhalaServerPage("KNX", path: "/knx", glyph: .radio, requirement: .component("knx")),
                KhalaServerPage("MQTT", path: "/config/mqtt", glyph: .radio, requirement: .component("mqtt")),
                KhalaServerPage("Thread", path: "/config/thread", glyph: .radio, requirement: .component("thread")),
                KhalaServerPage("Bluetooth", path: "/config/bluetooth", glyph: .radio, requirement: .component("bluetooth")),
                KhalaServerPage("Serial", path: "/config/serial", glyph: .radio, requirement: .component("usb")),
                KhalaServerPage("Modbus", path: "/config/modbus", glyph: .radio, requirement: .component("modbus")),
                KhalaServerPage("Tags", path: "/config/tags", glyph: .tags, requirement: .component("tag"), keywords: ["NFC"]),
            ]
        ),
        KhalaServerSection(
            id: "voice", title: "Voice assistants", path: "/config/voice-assistants", glyph: .voice,
            requirement: KhalaServerRequirement(),
            pages: [
                KhalaServerPage(
                    "Assistants", path: "/config/voice-assistants/assistants", glyph: .voice,
                    requirement: KhalaServerRequirement(), isTab: true
                ),
                KhalaServerPage(
                    "Expose", path: "/config/voice-assistants/expose", glyph: .entities,
                    requirement: KhalaServerRequirement(), isTab: true
                ),
            ],
            keywords: ["Assist", "Alexa", "Google"]
        ),
        KhalaServerSection(
            id: "people", title: "People", path: "/config/person", glyph: .people,
            requirement: .component("person", "users"),
            pages: [
                KhalaServerPage("People", path: "/config/person", glyph: .people, requirement: .component("person"), isTab: true),
                KhalaServerPage("Users", path: "/config/users", glyph: .users, isTab: true),
            ],
            badge: .people
        ),
        KhalaServerSection(
            id: "system", title: "System", path: "/config/system", glyph: .system, requirement: .core,
            pages: [
                KhalaServerPage("Home information", path: "/config/general", glyph: .general, keywords: ["Location", "Units"]),
                KhalaServerPage("Updates", path: "/config/updates", glyph: .updates, requirement: KhalaServerRequirement()),
                KhalaServerPage("Repairs", path: "/config/repairs", glyph: .repairs, requirement: KhalaServerRequirement()),
                KhalaServerPage("Logs", path: "/config/logs", glyph: .logs),
                KhalaServerPage("Backups", path: "/config/backup", glyph: .backups, requirement: .component("backup")),
                KhalaServerPage("Entity ID format", path: "/config/entity-id-format", glyph: .page),
                KhalaServerPage("Analytics", path: "/config/analytics", glyph: .analytics, requirement: KhalaServerRequirement()),
                KhalaServerPage("AI", path: "/config/ai", glyph: .page),
                KhalaServerPage("Labs", path: "/config/labs", glyph: .labs),
                KhalaServerPage("Network", path: "/config/network", glyph: .network, requirement: KhalaServerRequirement()),
                KhalaServerPage("Storage", path: "/config/storage", glyph: .storage, requirement: .component("hassio")),
                KhalaServerPage(
                    "Hardware", path: "/config/hardware", glyph: .hardware, requirement: .component("hassio", "hardware")
                ),
            ],
            badge: .attention,
            keywords: ["Restart", "Reboot"]
        ),
        KhalaServerSection(
            id: "tools", title: "Tools", path: "/config/tools", glyph: .tools, requirement: .core,
            keywords: ["Developer tools", "Template", "States", "Actions", "Services"]
        ),
        KhalaServerSection(
            id: "about", title: "About", path: "/config/info", glyph: .about, requirement: .core,
            keywords: ["Version"]
        ),
    ]

    /// The sections this server offers this user, in the frontend's order. Empty for a user who isn't an
    /// administrator (every settings page is admin-only, and the frontend has no settings panel for them).
    static func visibleSections(for server: KhalaServerCapabilities) -> [KhalaServerSection] {
        sections.filter { $0.requirement.isMet(by: server) }
    }

    /// The pages of `section` this server has.
    static func visiblePages(of section: KhalaServerSection, for server: KhalaServerCapabilities) -> [KhalaServerPage] {
        section.pages.filter { $0.requirement.isMet(by: server) }
    }

    // MARK: - Paths

    /// A frontend path as the catalog names pages: no query, no trailing slash, and no trailing `dashboard`
    /// segment (the config panel's routers default to it: `/config/integrations` shows
    /// `/config/integrations/dashboard`, `/config` shows `/config/dashboard`).
    static func normalized(_ path: String) -> String {
        var segments = KhalaFrontendPath.segments(path)
        if segments.count >= 2, segments.last == "dashboard" {
            segments.removeLast()
        }
        return "/" + segments.joined(separator: "/")
    }

    /// The frontend's own settings dashboard (`/config`, `/config/dashboard`), which the native Settings screen
    /// stands in for.
    static func isSettingsHome(_ path: String) -> Bool {
        normalized(path) == "/config"
    }

    /// The page of a section, or one of its tabs, as opposed to a page below them (an integration, a device, an
    /// automation's editor). Back from here goes to the native Settings screen, where the frontend's own back
    /// arrow would go to its settings dashboard.
    static func isSectionRoot(_ path: String) -> Bool {
        let path = normalized(path)
        return sections.contains { section in
            section.path == path || section.tabs.contains { $0.path == path }
        }
    }

    /// Whether the header's Back on `path` returns to the native Settings screen: on a section's own page or
    /// tab, or on the page Settings opened (`entryPath`, e.g. a search result such as Logs).
    static func backLeadsToSettings(path: String, entryPath: String?) -> Bool {
        if isSectionRoot(path) { return true }
        guard let entryPath else { return false }
        return normalized(entryPath) == normalized(path)
    }

    /// Whether `path` is `entry` or a page below it, segment-wise: where a page Settings opened landed after the
    /// frontend's own redirect (`/config/tools` → `/config/tools/yaml`, `/config/cloud` → `/config/cloud/start`).
    static func isLanding(_ path: String, of entry: String) -> Bool {
        let entry = KhalaFrontendPath.segments(normalized(entry))
        let path = KhalaFrontendPath.segments(normalized(path))
        return !entry.isEmpty && path.count >= entry.count && Array(path.prefix(entry.count)) == entry
    }

    /// The section whose tabs these are (a tabbed page reports its tabs' paths): its title names the page.
    static func section(forTabPaths paths: [String]) -> KhalaServerSection? {
        let paths = Set(paths.map(normalized))
        guard !paths.isEmpty else { return nil }
        return sections.first { section in
            let tabs = Set(section.tabs.map(\.path))
            return !tabs.isEmpty && paths.isSubset(of: tabs)
        }
    }

    /// The section a page belongs to: the longest section or page path that is a prefix of it, segment-wise.
    static func section(containing path: String) -> KhalaServerSection? {
        let segments = KhalaFrontendPath.segments(normalized(path))
        var best: (section: KhalaServerSection, length: Int)?
        for section in sections {
            for candidate in [section.path] + section.pages.map(\.path) {
                let prefix = KhalaFrontendPath.segments(candidate)
                guard prefix.count <= segments.count, Array(segments.prefix(prefix.count)) == prefix else { continue }
                if prefix.count > (best?.length ?? 0) {
                    best = (section, prefix.count)
                }
            }
        }
        return best?.section
    }

    // MARK: - Search

    /// Every section and page this server offers, for the Settings search.
    static func searchEntries(for server: KhalaServerCapabilities) -> [KhalaSettingsEntry] {
        visibleSections(for: server).flatMap { section -> [KhalaSettingsEntry] in
            let own = KhalaSettingsEntry(
                id: "server:" + section.path,
                title: section.title,
                subtitle: nil,
                glyph: section.glyph,
                keywords: section.keywords,
                target: .serverPage(path: section.path)
            )
            let pages = visiblePages(of: section, for: server)
                // A tab that only repeats its section ("Automations" under "Automations & scenes") still counts:
                // its own name is what people type.
                .map { page in
                    KhalaSettingsEntry(
                        id: "server:" + section.id + ":" + page.path,
                        title: page.title,
                        subtitle: section.title,
                        glyph: page.glyph,
                        keywords: page.keywords,
                        target: .serverPage(path: page.path)
                    )
                }
            return [own] + pages
        }
    }
}
