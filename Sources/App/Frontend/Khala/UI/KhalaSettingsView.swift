import SFSafeSymbols
import Shared
import SwiftUI

/// App and server settings in one screen (mockup `DaySettings`): a search over both, the server's card (name,
/// Home Assistant version, host, the amber attention chip), HOME ASSISTANT — the server's own settings sections
/// (`KhalaSettingsCatalog`, opened in the web UI under Khala's page chrome) — and THIS APP — the companion app's
/// own settings screens, which the shell pushes as they are, in Khala's appearance (`KhalaSettingsAppearance`).
/// Its only leading control is the shell's menu button.
struct KhalaSettingsView: View {
    let serverName: String
    @ObservedObject var settings: KhalaSettingsModel
    /// Live states: pending updates, automations and people are counted from them.
    @ObservedObject var live: KhalaLiveStates
    let onServerPage: (String) -> Void
    let onAppItem: (SettingsItem) -> Void
    let onAbout: () -> Void
    let onMoreAppSettings: () -> Void

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    /// The app's own screens the mockup lists, in its order; the rest are under "More app settings" and in the
    /// search.
    private static let appItems: [AppRow] = [
        AppRow(item: .servers, glyph: .servers), AppRow(item: .general, glyph: .appGeneral),
        AppRow(item: .gestures, glyph: .gestures), AppRow(item: .notifications, glyph: .notifications),
        AppRow(item: .liveActivities, glyph: .liveActivities), AppRow(item: .kiosk, glyph: .kiosk),
        AppRow(item: .privacy, glyph: .privacy),
    ]

    private struct AppRow: Identifiable {
        let item: SettingsItem
        let glyph: KhalaSettingsGlyph
        var id: SettingsItem { item }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(KhalaText.settings)
                    .font(KhalaTheme.largeTitle)
                    .kerning(0.3)
                    .foregroundStyle(KhalaTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 4)
                searchField
                    .padding(.top, 11)

                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    sections
                } else {
                    results
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            // Room for the shell's menu button above the title.
            .padding(.top, 9 + 44 + 4)
            .padding(.bottom, 24)
            .animation(.easeOut(duration: 0.2), value: query.isEmpty)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .onAppear { settings.refresh() }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemSymbol: .magnifyingglass)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KhalaTheme.tertiary)
            TextField(KhalaText.searchSettings, text: $query)
                .font(.system(size: 16))
                .foregroundStyle(KhalaTheme.ink)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityLabel(KhalaText.searchAllSettings)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemSymbol: .xmarkCircleFill)
                        .foregroundStyle(KhalaTheme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KhalaScreenText.close)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .khalaGlass(in: Capsule(), interactive: true)
    }

    private var searchEntries: [KhalaSettingsEntry] {
        let server = KhalaSettingsCatalog.searchEntries(for: settings.capabilities)
        let app = SettingsItem.allCases
            .filter { $0.isVisible && $0 != .help && $0 != .whatsNew }
            .map { item in
                KhalaSettingsEntry(
                    id: "app:" + item.rawValue,
                    title: item.title,
                    subtitle: KhalaText.thisApp,
                    glyph: Self.appItems.first { $0.item == item }?.glyph ?? .appGeneral,
                    keywords: item.searchKeywords,
                    target: .app(id: item.rawValue)
                )
            }
        let about = KhalaSettingsEntry(
            id: "app:about", title: KhalaText.aboutKhala, subtitle: KhalaText.thisApp, glyph: .appAbout,
            keywords: ["Version", "Acknowledgements"], target: .app(id: Self.aboutId)
        )
        return server + app + [about]
    }

    private static let aboutId = "khala.about"

    /// Updates, automations, people and repairs.
    private var status: KhalaServerStatus {
        KhalaServerStatus(entities: live.entities, repairs: settings.repairs)
    }

    @ViewBuilder
    private var results: some View {
        let found = KhalaSettingsSearch.results(for: query, in: searchEntries)
        if found.isEmpty {
            Text(KhalaText.noResults(query.trimmingCharacters(in: .whitespaces)))
                .font(KhalaTheme.body)
                .foregroundStyle(KhalaTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            KhalaSettingsCard {
                ForEach(Array(found.enumerated()), id: \.element.id) { index, entry in
                    KhalaSettingsRow(
                        title: entry.title,
                        subtitle: entry.subtitle,
                        glyph: entry.glyph,
                        style: isServer(entry) ? .server : .app,
                        showsDivider: index < found.count - 1
                    ) {
                        open(entry)
                    }
                }
            }
            .padding(.top, 16)
        }
    }

    private func isServer(_ entry: KhalaSettingsEntry) -> Bool {
        if case .serverPage = entry.target { return true }
        return false
    }

    private func open(_ entry: KhalaSettingsEntry) {
        isSearchFocused = false
        switch entry.target {
        case let .serverPage(path):
            onServerPage(path)
        case let .app(id):
            if id == Self.aboutId {
                onAbout()
            } else if let item = SettingsItem(rawValue: id) {
                onAppItem(item)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var sections: some View {
        serverCard
            .padding(.top, 16)

        let serverSections = KhalaSettingsCatalog.visibleSections(for: settings.capabilities)
        if !serverSections.isEmpty {
            caption(KhalaText.homeAssistantSection)
            KhalaSettingsCard {
                ForEach(Array(serverSections.enumerated()), id: \.element.id) { index, section in
                    KhalaSettingsRow(
                        title: section.title,
                        glyph: section.glyph,
                        style: .server,
                        figure: status.figure(for: section.badge),
                        attention: section.badge == .attention ? status.attentionText : nil,
                        showsDivider: index < serverSections.count - 1
                    ) {
                        onServerPage(section.path)
                    }
                }
            }
        } else if settings.capabilities.isAdmin == false {
            caption(KhalaText.homeAssistantSection)
            Text(KhalaText.serverSettingsUnavailable)
                .font(KhalaTheme.secondaryText)
                .foregroundStyle(KhalaTheme.tertiary)
                .padding(.horizontal, 4)
        }

        caption(KhalaText.thisAppSection)
        KhalaSettingsCard {
            ForEach(Self.appItems.filter { $0.item.isVisible }) { row in
                KhalaSettingsRow(
                    title: row.item.title,
                    glyph: row.glyph,
                    style: .app,
                    figure: row.item == .servers ? serverCount : nil
                ) {
                    onAppItem(row.item)
                }
            }
            KhalaSettingsRow(title: KhalaText.moreAppSettings, glyph: .more, style: .app, action: onMoreAppSettings)
            KhalaSettingsRow(
                title: KhalaText.aboutKhala,
                glyph: .appAbout,
                style: .app,
                showsDivider: false,
                action: onAbout
            )
        }

        Text(KhalaText.appVersion(
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        ))
        .font(.system(size: 12))
        .foregroundStyle(KhalaTheme.muted)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var serverCount: String? {
        let count = Current.servers.all.count
        return count > 0 ? "\(count)" : nil
    }

    private func caption(_ title: String) -> some View {
        Text(title)
            .font(KhalaTheme.caption)
            .kerning(1.1)
            .foregroundStyle(KhalaTheme.muted)
            .padding(.leading, 4)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    // MARK: - Server card

    private var serverCard: some View {
        let name = settings.capabilities.locationName ?? serverName
        return Button {
            onServerPage(status.attentionPath)
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: String(name.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(KhalaTheme.groundFlat)
                    .frame(width: 44, height: 44)
                    .background(KhalaTheme.ink, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(KhalaTheme.ink)
                        .lineLimit(1)
                    Text(KhalaText.serverSubtitle(version: settings.capabilities.version, host: settings.host))
                        .font(KhalaTheme.secondaryText)
                        .foregroundStyle(KhalaTheme.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let attention = status.attentionText {
                    KhalaAttentionChip(text: attention)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 76)
            .background(KhalaTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .khalaCardShadow()
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(KhalaPressStyle())
        .accessibilityElement(children: .combine)
    }
}
