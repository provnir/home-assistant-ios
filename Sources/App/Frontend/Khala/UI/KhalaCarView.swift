import SFSafeSymbols
import Shared
import SwiftUI

/// A car's screen (mockup `DayCar`), built from whatever its Home Assistant device exposes (`KhalaCarLayout`):
/// Overview (top-down car, battery with the charge-limit tick, controls grid, recent arrivals/departures),
/// Climate (target ±, start/stop, seat/steering/defrost) and Charging (limit, current, port, cable, power).
struct KhalaCarView: View {
    let device: KhalaDevice
    @ObservedObject var live: KhalaLiveStates
    let actions: KhalaScreenActions
    let calendar: Calendar
    /// Opens the media sheet for the car's own player.
    let onMedia: (String) -> Void

    @State private var tab = 0
    @State private var presence: [KhalaPresenceChange] = []
    /// A refresh was asked for and no newer data has arrived yet.
    @State private var refreshStarted: Date?

    private static let tabs = [
        KhalaSubTab(title: KhalaScreenText.overview, symbol: .car),
        KhalaSubTab(title: KhalaScreenText.climate, symbol: .fanblades),
        KhalaSubTab(title: KhalaScreenText.charging, symbol: .boltFill),
    ]

    private var layout: KhalaCarLayout {
        KhalaCarLayout(name: device.name, members: live.members(of: device), attributes: live.attributes)
    }

    var body: some View {
        let car = layout
        // The "Updated 4 min ago" line ages on its own, between state changes.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            KhalaDeviceScreen(
                subtitle: subtitle(car, now: context.date),
                tabs: Self.tabs,
                selection: $tab,
                category: .car,
                title: { KhalaLargeTitle(text: device.name) },
                trailing: { wakePill(car) },
                content: {
                    switch tab {
                    case 1: climate(car)
                    case 2: charging(car)
                    default: overview(car)
                    }
                },
                onRefresh: { await refresh(interval: KhalaRefreshThrottle.onPull) }
            )
        }
        // Opening the screen asks the integration for fresh data (throttled; never wakes the car).
        .task(id: device.id) { await refresh(interval: KhalaRefreshThrottle.onAppear) }
        .onChange(of: lastUpdated) { updated in
            if let started = refreshStarted, let updated, updated >= started { refreshStarted = nil }
        }
        .task(id: car.tracker?.entityId) {
            guard let tracker = car.tracker?.entityId else { return }
            let history = await actions.history(
                entityIds: [tracker],
                since: Current.date().addingTimeInterval(-3 * 86400)
            )
            presence = Array(KhalaHistory.presenceChanges(history[tracker] ?? []).prefix(4))
        }
    }

    // MARK: - Header

    private func subtitle(_ car: KhalaCarLayout, now: Date) -> String? {
        let model = device.memberEntityIds.lazy
            .compactMap { live.entitiesById[$0]?.deviceId }
            .compactMap { live.deviceModels[$0] }
            .first
        let parts = [model, car.placeText, freshness(now: now)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Refresh

    /// The newest `last_updated` among the car's entities (`KhalaEntityRefresh`).
    private var lastUpdated: Date? {
        KhalaEntityRefresh.lastUpdated(of: live.members(of: device))
    }

    /// "Updating…" while a refresh is out (at most 20 s), else "Updated 4 min ago".
    private func freshness(now: Date) -> String? {
        if let refreshStarted, now.timeIntervalSince(refreshStarted) < 20 { return KhalaScreenText.updating }
        return lastUpdated.map { KhalaScreenText.updated($0, now: now) }
    }

    /// `homeassistant.update_entity` for the car's entities, throttled per car. Only reads: the wake button is
    /// never named or pressed, so a sleeping car answers from what the integration last had.
    private func refresh(interval: TimeInterval) async {
        let started = Current.date()
        guard await actions.refresh(deviceKey: device.id, members: live.members(of: device), interval: interval) else {
            return
        }
        if let lastUpdated, lastUpdated >= started { return }
        refreshStarted = started
    }

    @ViewBuilder
    private func wakePill(_ car: KhalaCarLayout) -> some View {
        if let wake = car.wakeButtonId, car.isAwake != true {
            Button {
                Task { await actions.perform(KhalaServiceCall("button", "press", entityId: wake)) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemSymbol: .moonFill)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KhalaTheme.tertiary)
                    Text(car.isAwake == false ? KhalaScreenText.asleep : KhalaScreenText.wake)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KhalaTheme.ink)
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .khalaGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private func overview(_ car: KhalaCarLayout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            KhalaCarIllustration(isCharging: car.isCharging || car.chargingControls.contains { $0.glyph == .chargePort && $0.isActive })
                .frame(maxWidth: 322)
                .frame(maxWidth: .infinity)
            HStack(alignment: .lastTextBaseline) {
                Text(car.battery.map { "\(Int($0.rounded()))%" } ?? device.stateText)
                    .font(.system(size: 52, weight: .semibold))
                    .kerning(-1.5)
                    .foregroundStyle(KhalaTheme.ink)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let range = car.rangeText {
                        Text(range).font(.system(size: 17, weight: .semibold)).foregroundStyle(KhalaTheme.ink)
                    }
                    if let charging = car.chargingText {
                        Text(charging).font(KhalaTheme.secondaryText).foregroundStyle(KhalaTheme.tertiary)
                    }
                }
                .padding(.bottom, 4)
            }
            if let battery = car.battery {
                KhalaBatteryBar(level: battery, limit: car.chargeLimit?.value)
            }
        }
        .khalaCard(padding: 18)

        controlsGrid(car.overview, car: car, extras: true)
            .padding(.top, 16)

        if !presence.isEmpty {
            KhalaSectionHeader(title: KhalaScreenText.recent)
            VStack(spacing: 0) {
                ForEach(Array(presence.enumerated()), id: \.element.id) { index, change in
                    KhalaPlainTimelineRow(
                        time: KhalaText.time(change.date, calendar: calendar),
                        text: presenceText(change),
                        detail: dayDetail(change.date),
                        dot: index == 0 ? .past(.car) : .upcoming(.car),
                        lineAbove: index == 0 ? nil : KhalaTheme.line,
                        lineBelow: index == presence.count - 1 ? nil : KhalaTheme.line
                    )
                }
            }
        }
    }

    private func presenceText(_ change: KhalaPresenceChange) -> String {
        let place = change.place == "home" ? "home" : KhalaText.humanized(state: change.place)
        return change.arrived ? "\(KhalaScreenText.arrived) \(place)" : "\(KhalaScreenText.left) \(place)"
    }

    private func dayDetail(_ date: Date) -> String? {
        if calendar.isDateInToday(date) { return nil }
        if calendar.isDateInYesterday(date) { return KhalaScreenText.yesterday }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter.string(from: date)
    }

    /// The controls in a wrapping three-column grid; on Overview also the car's media player and a "More" tile
    /// for the buttons Khala has no glyph for.
    @ViewBuilder
    private func controlsGrid(_ controls: [KhalaControl], car: KhalaCarLayout, extras: Bool = false) -> some View {
        let showsMedia = extras && car.mediaPlayerId != nil
        let showsMore = extras && !car.moreControls.isEmpty
        if !controls.isEmpty || showsMedia || showsMore {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(controls) { control in
                    KhalaControlTile(control: control, category: .car) { call in send(call, car: car) }
                }
                if showsMedia, let player = car.mediaPlayerId {
                    Button { onMedia(player) } label: { extraTile(KhalaScreenText.media, symbol: .musicNote) }
                        .buttonStyle(.plain)
                }
                if showsMore {
                    Menu {
                        ForEach(car.moreControls) { control in
                            Button(control.title) {
                                if let plan = control.call { send(plan.call, car: car) }
                            }
                            .disabled(control.call == nil)
                        }
                    } label: {
                        extraTile(KhalaScreenText.more, symbol: .ellipsis)
                    }
                }
            }
        }
    }

    private func extraTile(_ title: String, symbol: SFSymbol) -> some View {
        VStack(spacing: 6) {
            Image(systemSymbol: symbol)
                .font(.system(size: 20, weight: .medium))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(KhalaTheme.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(KhalaTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .khalaCardShadow()
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Sends a car command, pressing the car's wake button first while it reports being asleep. Opening the
    /// screen never wakes it.
    private func send(_ call: KhalaServiceCall, car: KhalaCarLayout) {
        Task {
            if car.needsWake, let wake = car.wakeButtonId, call.entityId != wake {
                await actions.perform(KhalaServiceCall("button", "press", entityId: wake))
            }
            await actions.perform(call)
        }
    }

    // MARK: - Climate

    @ViewBuilder
    private func climate(_ car: KhalaCarLayout) -> some View {
        if let climate = car.climate {
            VStack(spacing: 16) {
                if let target = climate.target {
                    KhalaNumberStepper(setting: target, category: .car, large: true) { value in
                        send(climate.setTarget(value), car: car)
                    }
                }
                HStack(spacing: 20) {
                    if let inside = car.insideTemperature ?? climate.currentTemperature {
                        temperature(KhalaScreenText.inside, inside)
                    }
                    if let outside = car.outsideTemperature {
                        temperature(KhalaScreenText.outside, outside)
                    }
                }
                Button {
                    send(climate.power(on: !climate.isOn), car: car)
                } label: {
                    Label(
                        climate.isOn ? KhalaScreenText.stop : KhalaScreenText.start,
                        systemSymbol: climate.isOn ? .stopFill : .playFill
                    )
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(climate.isOn ? KhalaTheme.ink : Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        climate.isOn ? KhalaTheme.groundFlat : KhalaTheme.accent(.car),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }
            .khalaCard(padding: 18)
        } else {
            Text(KhalaScreenText.noClimate)
                .font(KhalaTheme.body)
                .foregroundStyle(KhalaTheme.secondary)
                .khalaCard()
        }
        controlsGrid(car.climateControls, car: car)
            .padding(.top, 16)
    }

    private func temperature(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(KhalaText.measurement(value, unit: "°"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(KhalaTheme.ink)
            Text(title)
                .font(KhalaTheme.secondaryText)
                .foregroundStyle(KhalaTheme.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Charging

    @ViewBuilder
    private func charging(_ car: KhalaCarLayout) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline) {
                Text(car.battery.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(KhalaTheme.ink)
                Spacer()
                if let text = car.chargingText {
                    Text(text)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(car.isCharging ? KhalaTheme.accent(.car) : KhalaTheme.tertiary)
                }
            }
            if let battery = car.battery {
                KhalaBatteryBar(level: battery, limit: car.chargeLimit?.value)
                    .padding(.bottom, 6)
            }
            if let limit = car.chargeLimit {
                KhalaNumberStepper(setting: limit, category: .car) { value in
                    send(limit.call(value: value), car: car)
                }
                .padding(.vertical, 6)
            }
            if let current = car.chargeCurrent {
                KhalaNumberStepper(setting: current, category: .car) { value in
                    send(current.call(value: value), car: car)
                }
                .padding(.vertical, 6)
            }
            if let power = car.chargerPowerText {
                KhalaInfoRow(title: KhalaScreenText.chargerPower, value: power)
            }
            if let full = car.timeToFull {
                KhalaInfoRow(title: KhalaScreenText.fullAt, value: KhalaText.time(full, calendar: calendar))
            }
        }
        .khalaCard(padding: 18)
        controlsGrid(car.chargingControls, car: car)
            .padding(.top, 16)
    }
}
