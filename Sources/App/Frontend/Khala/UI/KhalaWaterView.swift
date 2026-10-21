import SFSafeSymbols
import Shared
import SwiftUI

/// The hot-water screen (mockup `DayWater`) for a heat device: Now (24 h dial with the sun band, the windows its
/// automations heat in and a now marker; duration + Heat now; tonight's automations), Schedule (every automation
/// that runs it on a clock, each with its switch) and History (when it was on, from the recorder).
struct KhalaWaterView: View {
    let device: KhalaDevice
    @ObservedObject var live: KhalaLiveStates
    let actions: KhalaScreenActions
    let now: Date
    let calendar: Calendar

    @State private var tab = 0
    @State private var minutes = KhalaHeatLayout.defaultDuration
    @State private var runs: [KhalaRun]? = nil

    private static let tabs = [
        KhalaSubTab(title: KhalaScreenText.now, symbol: .dropFill),
        KhalaSubTab(title: KhalaScreenText.schedule, symbol: .clock),
        KhalaSubTab(title: KhalaScreenText.history, symbol: .listBullet),
    ]

    var body: some View {
        let members = live.members(of: device)
        let heater = live.entitiesById[device.primaryEntityId]
        let memberIds = Set(device.memberEntityIds)
        KhalaDeviceScreen(
            subtitle: subtitle(heater: heater),
            tabs: Self.tabs,
            selection: $tab,
            category: .heat,
            title: { KhalaLargeTitle(text: device.name) },
            trailing: { EmptyView() },
            content: {
                if let heater {
                    let heat = KhalaHeatLayout(heater: heater, platform: live.platforms[heater.entityId], members: members)
                    switch tab {
                    case 1: schedule(memberIds: memberIds)
                    case 2: history
                    default: nowTab(heat, memberIds: memberIds)
                    }
                } else {
                    Text(KhalaScreenText.unknownDevice)
                        .font(KhalaTheme.body)
                        .foregroundStyle(KhalaTheme.secondary)
                }
            }
        )
        .task(id: tab == 2) {
            guard tab == 2 else { return }
            let history = await actions.history(
                entityIds: [device.primaryEntityId],
                since: Current.date().addingTimeInterval(-7 * 86400)
            )
            runs = KhalaHistory.runs(history[device.primaryEntityId] ?? [], now: Current.date())
        }
    }

    private func subtitle(heater: KhalaEntity?) -> String? {
        let model = heater?.deviceId.flatMap { live.deviceModels[$0] }
        return model ?? heater.map { KhalaText.humanized(state: $0.domain.replacingOccurrences(of: "_", with: " ")) }
    }

    private func automations(memberIds: Set<String>, horizon: TimeInterval) -> [KhalaDeviceAutomation] {
        KhalaDeviceAutomations.related(
            to: memberIds,
            configs: live.automationConfigs,
            entities: live.entities,
            now: now,
            horizon: horizon,
            calendar: calendar
        )
    }

    // MARK: - Now

    @ViewBuilder
    private func nowTab(_ heat: KhalaHeatLayout, memberIds: Set<String>) -> some View {
        let related = automations(memberIds: memberIds, horizon: 86400)
        let sun = live.entities.first { $0.domain == "sun" }
        let dial = KhalaDayDial.build(sun: sun, automations: related, now: now, calendar: calendar)
        VStack(spacing: 14) {
            KhalaDayDialView(dial: dial, isOn: heat.isOn) {
                VStack(spacing: 6) {
                    Text(heat.stateText)
                        .font(.system(size: 44, weight: .semibold))
                        .kerning(-1)
                        .foregroundStyle(KhalaTheme.ink)
                    if let chip = chipText(heat, sun: sun) {
                        HStack(spacing: 5) {
                            Image(systemSymbol: heat.isOn ? .flameFill : .sunMaxFill)
                                .font(.system(size: 12, weight: .semibold))
                            Text(chip)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(heat.isOn ? KhalaTheme.accent(.heat) : KhalaTheme.accent(.sun))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(heat.isOn ? KhalaTheme.tint(.heat) : KhalaTheme.tint(.sun), in: Capsule())
                    }
                }
            }
            .frame(width: 220, height: 220)
            .frame(maxWidth: .infinity)

            if heat.isOn {
                actionButton(KhalaScreenText.turnOff, symbol: .power, filled: false) {
                    Task { await actions.perform(heat.offCall) }
                }
            } else {
                if heat.supportsDuration {
                    KhalaDurationPicker(durations: KhalaHeatLayout.durations, selection: $minutes)
                }
                actionButton(
                    KhalaScreenText.heatNow(minutes: heat.supportsDuration ? minutes : nil),
                    symbol: .flameFill,
                    filled: true
                ) {
                    Task { await actions.perform(heat.heatCall(minutes: minutes)) }
                }
                .disabled(heat.isUnavailable)
            }
        }
        .khalaCard(padding: 18)

        let tonight = related.filter { !$0.fireDates.isEmpty }
        if !tonight.isEmpty {
            KhalaSectionHeader(title: KhalaScreenText.tonight)
            // Newest on top (`KhalaTimelineOrder`): the latest run first, the next one just above Now.
            let order = KhalaTimelineOrder(
                upcoming: tonight,
                past: [],
                date: { $0.fireDates.first ?? .distantFuture },
                showsNow: true
            )
            VStack(spacing: 0) {
                ForEach(order.rows) { row in
                    if let automation = row.item {
                        KhalaTimelineRow(
                            time: automation.fireDates.first.map { KhalaText.time($0, calendar: calendar) } ?? "",
                            isNow: false,
                            dot: .upcoming(automation.isEnabled ? .heat : .neutral),
                            dotCenter: 22,
                            lineAbove: KhalaTheme.stroke(row.strokeAbove),
                            lineBelow: KhalaTheme.stroke(row.strokeBelow)
                        ) {
                            KhalaAutomationCard(automation: automation, category: .heat) {
                                Task { await actions.perform(automation.toggleCall) }
                            }
                        }
                    } else {
                        KhalaPlainTimelineRow(
                            time: KhalaText.now,
                            text: heat.stateText,
                            detail: nil,
                            dot: .now,
                            lineAbove: KhalaTheme.stroke(row.strokeAbove),
                            lineBelow: KhalaTheme.stroke(row.strokeBelow),
                            isNow: true
                        )
                    }
                }
            }
        }
    }

    private func chipText(_ heat: KhalaHeatLayout, sun: KhalaEntity?) -> String? {
        if heat.isOn {
            if let remaining = heat.remaining, remaining > 0 { return KhalaScreenText.left(remaining) }
            return heat.powerText.map { "\(KhalaScreenText.heating) · \($0)" } ?? KhalaScreenText.heating
        }
        return sun?.state == "above_horizon" ? KhalaScreenText.sunsOnIt : nil
    }

    private func actionButton(_ title: String, symbol: SFSymbol, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemSymbol: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KhalaTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(filled ? Self.heatButton : KhalaTheme.groundFlat, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// DESIGN.md: water/heat button fill `#f2b061` with ink text.
    private static var heatButton: Color { Color(red: 242 / 255, green: 176 / 255, blue: 97 / 255) }

    // MARK: - Schedule

    @ViewBuilder
    private func schedule(memberIds: Set<String>) -> some View {
        let all = automations(memberIds: memberIds, horizon: 7 * 86400)
        if all.isEmpty {
            Text(KhalaScreenText.noSchedule)
                .font(KhalaTheme.body)
                .foregroundStyle(KhalaTheme.secondary)
                .khalaCard()
        } else {
            // Newest on top: the latest next run first, the soonest last; those with no next run at the bottom.
            VStack(spacing: 10) {
                ForEach(KhalaTimelineLine.latestFirst(all, date: { $0.fireDates.first })) { automation in
                    KhalaAutomationCard(automation: automation, category: .heat, detail: nextText(automation)) {
                        Task { await actions.perform(automation.toggleCall) }
                    }
                }
            }
        }
    }

    private func nextText(_ automation: KhalaDeviceAutomation) -> String? {
        if let next = automation.fireDates.first {
            let day = calendar.isDateInToday(next) ? KhalaText.today
                : calendar.isDateInTomorrow(next) ? KhalaScreenText.tomorrow : Self.dayFormatter.string(from: next)
            return "\(day) \(KhalaText.time(next, calendar: calendar))"
        }
        guard !automation.timesOfDay.isEmpty else { return nil }
        return automation.timesOfDay
            .map { KhalaDayDial.text(.init(start: $0, end: $0)) }
            .joined(separator: ", ")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    // MARK: - History

    @ViewBuilder
    private var history: some View {
        if let runs {
            if runs.isEmpty {
                Text(KhalaScreenText.noHistory)
                    .font(KhalaTheme.body)
                    .foregroundStyle(KhalaTheme.secondary)
                    .khalaCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(runs) { run in
                        KhalaInfoRow(title: runTitle(run), value: KhalaText.duration(run.duration(now: now)))
                        if run.id != runs.last?.id { Divider() }
                    }
                }
                .khalaCard(padding: 16)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }

    private func runTitle(_ run: KhalaRun) -> String {
        let day = calendar.isDateInToday(run.start) ? KhalaText.today : Self.dayFormatter.string(from: run.start)
        let end = run.end.map { KhalaText.time($0, calendar: calendar) } ?? KhalaScreenText.ongoing
        return "\(day) \(KhalaText.time(run.start, calendar: calendar))–\(end)"
    }
}
