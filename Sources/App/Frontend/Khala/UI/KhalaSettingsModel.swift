import Combine
import Foundation
import HAKit
import Shared

/// Feeds the Settings screen from the server: what it offers (`get_config` → loaded integrations, version, home
/// name), whether the user is an administrator (`caches.user`), open repairs (`repairs/list_issues`, admin
/// only — left out when the server refuses), and the host the app talks to. Counts that come from live states
/// (updates, automations, people) are the shell's (`KhalaHomeViewModel.live`), not fetched again here.
@MainActor
final class KhalaSettingsModel: ObservableObject {
    @Published private(set) var capabilities = KhalaServerCapabilities()
    @Published private(set) var repairs: Int?
    @Published private(set) var host: String?

    let server: Server
    private var userToken: HACancellable?

    init(server: Server) {
        self.server = server
    }

    deinit {
        userToken?.cancel()
    }

    /// Fetches everything again (on every appearance: a new integration or a fixed repair shows up next time).
    func refresh() {
        guard let api = Current.api(for: server) else { return }
        api.connectWebSocketIfNeeded()
        if userToken == nil {
            // Same subscription as `MacSidebarViewModel`'s admin flag.
            userToken = api.connection.caches.user.subscribe { [weak self] _, user in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.capabilities.isAdmin != user.isAdmin {
                        self.capabilities.isAdmin = user.isAdmin
                    }
                    self.fetchRepairs()
                }
            }
        }
        // Same call shape as `KhalaHomeViewModel.fetchMissingAutomationConfigs`.
        api.connection.send(.init(type: .webSocket("get_config"), data: [:])) { [weak self] result in
            switch result {
            case let .success(data):
                guard case let .dictionary(config) = data else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let merged = self.capabilities.merging(config: config)
                    if merged != self.capabilities { self.capabilities = merged }
                }
            case let .failure(error):
                Current.Log.info("Khala settings: get_config failed: \(error.localizedDescription)")
            }
        }
        fetchRepairs()
        Task { [weak self, server] in
            let host = await server.activeURL()?.host
            await MainActor.run { [weak self] in
                if self?.host != host { self?.host = host }
            }
        }
    }

    /// Open repairs; admin-only on the server (`require_admin`), so only asked for an administrator, and left
    /// out (nil) when refused.
    private func fetchRepairs() {
        guard capabilities.isAdmin == true, let api = Current.api(for: server) else {
            if capabilities.isAdmin == false { repairs = nil }
            return
        }
        api.connection.send(.init(type: .webSocket("repairs/list_issues"), data: [:])) { [weak self] result in
            let count: Int?
            switch result {
            case let .success(data):
                if case let .dictionary(answer) = data {
                    count = KhalaServerStatus.openRepairs(in: answer)
                } else {
                    count = nil
                }
            case let .failure(error):
                Current.Log.info("Khala settings: repairs/list_issues refused: \(error.localizedDescription)")
                count = nil
            }
            Task { @MainActor [weak self] in
                if self?.repairs != count { self?.repairs = count }
            }
        }
    }
}
