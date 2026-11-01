import SFSafeSymbols
import Shared
import SwiftUI
import UIKit

/// A car's screen (mockup `DayCar`), built from whatever its Home Assistant device exposes (`KhalaCarLayout`):
/// Overview (top-down car, battery with the charge-limit tick, controls grid, recent arrivals/departures),
/// Climate (target ±, start/stop, seat/steering/defrost) and Charging (limit, current, port, cable, power).
struct KhalaCarView: View {
    let device: KhalaDevice
    @ObservedObject var live: KhalaLiveStates
    /// The optimistic overlay of the car's controls (`live.pending`), observed for the steppers and Start/Stop.
    @ObservedObject var pending: KhalaPendingStore
    let actions: KhalaScreenActions
    let calendar: Calendar
    /// Opens the media sheet for the car's own player.
    let onMedia: (String) -> Void

    @State private var tab = 0
    @State private var presence: [KhalaPresenceChange] = []
    /// Waking the car / asking for fresh data, shown on the trailing pill.
    @State private var sync: KhalaCarSyncState = .idle

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
                trailing: { syncPill(car) },
                content: {
                    switch tab {
                    case 1: climate(car)
                    case 2: charging(car)
                    default: overview(car)
                    }
                },
                onRefresh: { await refresh(explicit: true) }
            )
        }
        // Opening the screen wakes the car if it sleeps and reads it (not again within a minute of the last read).
        .task(id: device.id) { await refresh(explicit: false) }
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

    /// "Waking car…" / "Updating…" while a refresh runs, "Car didn't wake" after a failed wake, else
    /// "Updated 4 min ago" (`KhalaCarSyncState.freshnessText`).
    private func freshness(now: Date) -> String? {
        sync.freshnessText(lastUpdated: lastUpdated, now: now)
    }

    /// Wakes the car when it sleeps (Nir: a refresh must wake it to read its status), then
    /// `homeassistant.update_entity` for its entities. Opening the screen skips it within a minute of the last
    /// completed refresh; "Refresh now" and pull to refresh always run (never two at once).
    private func refresh(explicit: Bool) async {
        let key = actions.refreshKey(device.id)
        if !explicit, !KhalaScreenActions.refreshes.allowsAutomatic(key, now: Current.date()) { return }
        guard KhalaScreenActions.refreshes.begin(key) else { return }
        guard await wake() else {
            KhalaScreenActions.refreshes.finish(key, now: Current.date(), completed: false)
            sync = .didntWake
            return
        }
        sync = .updating
        let ok = await actions.updateEntities(of: live.members(of: device))
        KhalaScreenActions.refreshes.finish(key, now: Current.date(), completed: ok)
        sync = .idle
    }

    /// Presses the wake button when the car is asleep or offline and waits (up to `KhalaCarWakePlan.timeout`) for
    /// its connectivity sensor to report it online. True when it is awake, or there is nothing to wake it with.
    private func wake() async -> Bool {
        switch layout.wakePlan {
        case .none:
            return true
        case let .press(button):
            sync = .waking
            return await actions.press(button)
        case let .pressAndWait(button, connectivity):
            sync = .waking
            guard await actions.press(button) else { return false }
            let deadline = Current.date().addingTimeInterval(KhalaCarWakePlan.timeout)
            // The live states follow the websocket, so the sensor flips here as soon as Home Assistant sees it.
            while Current.date() < deadline, !Task.isCancelled {
                if live.entitiesById[connectivity]?.state == "on" { return true }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            return live.entitiesById[connectivity]?.state == "on"
        }
    }

    /// Top right: "Refresh now" (a moon while the car sleeps), "Waking car…", "Updating…", or "Retry" after a
    /// failed wake.
    private func syncPill(_ car: KhalaCarLayout) -> some View {
        Button {
            Task { await refresh(explicit: true) }
        } label: {
            HStack(spacing: 7) {
                switch sync {
                case .waking, .updating:
                    ProgressView()
                        .controlSize(.small)
                case .didntWake:
                    Image(systemSymbol: .exclamationmarkTriangleFill)
                        .font(KhalaTheme.smallGlyph)
                        .foregroundStyle(KhalaTheme.accent(.heat))
                case .idle:
                    Image(systemSymbol: car.isAwake == false ? .moonFill : .arrowClockwise)
                        .font(KhalaTheme.smallGlyph)
                        .foregroundStyle(KhalaTheme.tertiary)
                }
                Text(syncTitle)
                    .font(KhalaTheme.rowValue)
                    .foregroundStyle(KhalaTheme.ink)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .khalaGlass(in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(sync == .waking || sync == .updating)
        .animation(.easeOut(duration: 0.2), value: sync)
    }

    private var syncTitle: String {
        switch sync {
        case .idle: return KhalaScreenText.refreshNow
        case .waking: return KhalaScreenText.wakingCar
        case .updating: return KhalaScreenText.updating
        case .didntWake: return KhalaScreenText.retry
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
                    .font(KhalaTheme.heroFigure)
                    .kerning(-1.5)
                    .foregroundStyle(KhalaTheme.ink)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let range = car.rangeText {
                        Text(range).font(KhalaTheme.figure).foregroundStyle(KhalaTheme.ink)
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
            // Newest on top (`KhalaTimelineOrder`); all of it happened, so filled dots on the ink line.
            let recent = KhalaTimelineOrder(upcoming: [], past: presence, date: \.date, showsNow: false)
            VStack(spacing: 0) {
                ForEach(recent.rows) { row in
                    if let change = row.item {
                        KhalaPlainTimelineRow(
                            time: KhalaText.time(change.date, calendar: calendar),
                            text: presenceText(change),
                            detail: dayDetail(change.date),
                            dot: .past(.car),
                            lineAbove: KhalaTheme.stroke(row.strokeAbove),
                            lineBelow: KhalaTheme.stroke(row.strokeBelow)
                        )
                    }
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

    /// The controls in the shared wrapping three-column grid; on Overview also the car's media player and a "More"
    /// tile for the buttons Khala has no glyph for.
    @ViewBuilder
    private func controlsGrid(_ controls: [KhalaControl], car: KhalaCarLayout, extras: Bool = false) -> some View {
        let showsMedia = extras && car.mediaPlayerId != nil
        let showsMore = extras && !car.moreControls.isEmpty
        KhalaControlGrid(
            controls: models(controls),
            category: .car,
            pending: pending,
            hasExtras: showsMedia || showsMore,
            onIntent: { control, intent in send(intent, on: control, car: car) }
        ) {
            if showsMedia, let player = car.mediaPlayerId {
                Button { onMedia(player) } label: { extraTile(KhalaScreenText.media, symbol: .musicNote) }
                    .buttonStyle(.plain)
            }
            if showsMore {
                Menu {
                    ForEach(models(car.moreControls)) { control in
                        Button(control.title) {
                            if let intent = control.tapIntent { send(intent, on: control, car: car) }
                        }
                        .disabled(control.tapIntent == nil)
                    }
                } label: {
                    extraTile(KhalaScreenText.more, symbol: .ellipsis)
                }
            }
        }
    }

    /// The layout's tiles as the grid's models.
    private func models(_ controls: [KhalaControl]) -> [KhalaControlModel] {
        controls.compactMap { control in
            live.entitiesById[control.entityId].map {
                KhalaControlModel(control, entity: $0, attributes: live.attributes[control.entityId] ?? [:])
            }
        }
    }

    private func extraTile(_ title: String, symbol: SFSymbol) -> some View {
        VStack(spacing: 6) {
            Image(systemSymbol: symbol)
                .font(KhalaTheme.tileGlyph)
            Text(title)
                .font(KhalaTheme.tileLabel)
        }
        .foregroundStyle(KhalaTheme.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(KhalaTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .khalaCardShadow()
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Sends a car command through the shared pending store: the control shows its new state at once, the car is
    /// woken first while it is asleep or offline (and waited for), then the command goes out and the car is read
    /// again so the screen settles on the real result. A double tap while it is out is dropped.
    private func send(_ intent: KhalaIntent, on control: KhalaControlModel, car: KhalaCarLayout) {
        Task {
            let needsWake = control.entityId != car.wakeButtonId && car.wakePlan != .none
            let prepare: (() async -> Bool)? = needsWake ? { await wakeForCommand() } : nil
            let ok = await pending.run(intent, on: control, live: live, actions: actions, prepare: prepare)
            guard ok else { return }
            let key = actions.refreshKey(device.id)
            guard KhalaScreenActions.refreshes.begin(key) else { return }
            sync = .updating
            let updated = await actions.updateEntities(of: live.members(of: device))
            KhalaScreenActions.refreshes.finish(key, now: Current.date(), completed: updated)
            sync = .idle
        }
    }

    /// The wake before a command; "Car didn't wake" and the error haptic when it doesn't.
    private func wakeForCommand() async -> Bool {
        guard await wake() else {
            sync = .didntWake
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
        sync = .idle
        return true
    }

    // MARK: - Climate

    @ViewBuilder
    private func climate(_ car: KhalaCarLayout) -> some View {
        if let climate = car.climate {
            let power = pending.shown(KhalaControlModel(
                entityId: climate.entityId, title: KhalaScreenText.climate, symbol: .sf("fanblades"),
                kind: .toggle(isOn: climate.isOn), confirm: nil
            ))
            let isOn = power.toggleIsOn ?? climate.isOn
            VStack(spacing: 16) {
                if let target = climate.target {
                    let control = KhalaControlModel.stepper(target, symbolName: "thermometer.medium")
                    KhalaNumberStepper(setting: pending.shown(control).numberSetting ?? target, category: .car,
                                       large: true) { value in
                        if let intent = control.valueIntent(value) { send(intent, on: control, car: car) }
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
                    send(.setOn(!isOn), on: power, car: car)
                } label: {
                    Label(
                        isOn ? KhalaScreenText.stop : KhalaScreenText.start,
                        systemSymbol: isOn ? .stopFill : .playFill
                    )
                    .font(KhalaTheme.rowTitle)
                    .foregroundStyle(isOn ? KhalaTheme.ink : Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        isOn ? KhalaTheme.groundFlat : KhalaTheme.accent(.car),
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
                .font(KhalaTheme.figure)
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
                    .font(KhalaTheme.heroFigureSmall)
                    .foregroundStyle(KhalaTheme.ink)
                Spacer()
                if let text = car.chargingText {
                    Text(text)
                        .font(KhalaTheme.rowValue)
                        .foregroundStyle(car.isCharging ? KhalaTheme.accent(.car) : KhalaTheme.tertiary)
                }
            }
            if let battery = car.battery {
                KhalaBatteryBar(level: battery, limit: car.chargeLimit?.value)
                    .padding(.bottom, 6)
            }
            if let limit = car.chargeLimit {
                let control = KhalaControlModel.stepper(limit, symbolName: "bolt.fill")
                KhalaNumberStepper(setting: pending.shown(control).numberSetting ?? limit, category: .car) { value in
                    if let intent = control.valueIntent(value) { send(intent, on: control, car: car) }
                }
                .padding(.vertical, 6)
            }
            if let current = car.chargeCurrent {
                let control = KhalaControlModel.stepper(current, symbolName: "bolt.fill")
                KhalaNumberStepper(setting: pending.shown(control).numberSetting ?? current, category: .car) { value in
                    if let intent = control.valueIntent(value) { send(intent, on: control, car: car) }
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
