import SFSafeSymbols
import SwiftUI

/// Today: the home's day as a vertical timeline (mockup `DayHome`). Past above "Now", upcoming below; the Now card
/// holds live device chips. Floating glass buttons open the menu and its search; everything else is solid. The
/// ground is drawn by the shell, clipped to the card's rounded shape while the menu is open.
struct KhalaTodayView: View {
    let timeline: KhalaTimeline
    let now: Date
    let calendar: Calendar
    let onMenu: () -> Void
    let onSearch: () -> Void
    let onItem: (KhalaTimelineItem) -> Void
    let onDevice: (KhalaDevice) -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter
    }()

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(KhalaText.today)
                        .font(KhalaTheme.largeTitle)
                        .kerning(0.3)
                        .foregroundStyle(KhalaTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: "\(Self.dateFormatter.string(from: now)) · \(timeline.summary)")
                        .font(KhalaTheme.headerSubtitle)
                        .foregroundStyle(KhalaTheme.secondary)
                        .padding(.top, 1)
                        .padding(.bottom, 26)

                    let items = timeline.items
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let isFirst = index == 0
                        let isLast = index == items.count - 1
                        // Ink through the past up to Now, the light line after it and past the last row.
                        let throughPast = item.isPast || item.isNow
                        let lineAbove: Color? = isFirst ? nil : (throughPast ? KhalaTheme.ink : KhalaTheme.line)
                        let lineBelow: Color? = item.isPast && !isLast ? KhalaTheme.ink : KhalaTheme.line
                        let time = item.isNow ? KhalaText.now : KhalaText.time(item.date, calendar: calendar)
                        switch item.kind {
                        case .sunrise, .sunset:
                            KhalaTimelineRow(
                                time: time,
                                isNow: false,
                                dot: item.isPast ? .past(item.category) : .upcoming(item.category),
                                dotCenter: 11,
                                lineAbove: lineAbove,
                                lineBelow: lineBelow
                            ) {
                                Text(item.title)
                                    .font(KhalaTheme.body)
                                    .foregroundStyle(KhalaTheme.muted)
                                    .frame(height: 22)
                            }
                        case .now:
                            KhalaTimelineRow(
                                time: time,
                                isNow: true,
                                dot: .now,
                                dotCenter: 24.5,
                                lineAbove: lineAbove,
                                lineBelow: lineBelow
                            ) {
                                KhalaNowCard(headline: timeline.headline, chips: timeline.chips, onDevice: onDevice)
                            }
                        case .detection:
                            KhalaTimelineRow(
                                time: time,
                                isNow: false,
                                dot: item.isPast ? .past(item.category) : .upcoming(item.category),
                                dotCenter: 22.5,
                                lineAbove: lineAbove,
                                lineBelow: lineBelow
                            ) {
                                KhalaEventCard(title: item.title, subtitle: item.subtitle, category: item.category) {
                                    onItem(item)
                                }
                            }
                        case .scheduled, .timestamp:
                            KhalaTimelineRow(
                                time: time,
                                isNow: false,
                                dot: item.isPast ? .past(item.category) : .upcoming(item.category),
                                dotCenter: KhalaUpcomingCard.height / 2,
                                lineAbove: lineAbove,
                                lineBelow: lineBelow
                            ) {
                                KhalaUpcomingCard(
                                    title: item.title,
                                    subtitle: item.subtitle,
                                    category: item.category,
                                    action: item.targetEntityId == nil ? nil : { onItem(item) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, KhalaTheme.gutter)
                // Room for the floating buttons above the title, and for the line to run on below the last row.
                .padding(.top, 9 + 44 + 4)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)

            HStack {
                KhalaGlassButton(symbol: .sidebarLeft, accessibilityLabel: KhalaText.openMenu, action: onMenu)
                Spacer()
                KhalaGlassButton(symbol: .magnifyingglass, accessibilityLabel: KhalaText.search, action: onSearch)
            }
            .padding(.horizontal, 16)
            .padding(.top, 9)
        }
    }
}

#Preview {
    let calendar = Calendar.current
    let now = Date()
    let sun = KhalaEntity(
        entityId: "sun.sun",
        state: "above_horizon",
        lastChanged: now,
        attributes: [
            "next_rising": "2099-01-01T06:00:00Z",
            "next_setting": "2099-01-01T18:00:00Z",
        ]
    )
    let devices = [
        KhalaDevice(
            id: "a", name: "Rover", category: .car, primaryEntityId: "sensor.a",
            stateText: "72%", memberEntityIds: [], isPinned: false
        ),
        KhalaDevice(
            id: "b", name: "Hot water", category: .heat, primaryEntityId: "switch.b",
            stateText: "Off", memberEntityIds: [], isPinned: true
        ),
        KhalaDevice(
            id: "c", name: "Theater", category: .media, primaryEntityId: "media_player.c",
            stateText: "Off", memberEntityIds: [], isPinned: false
        ),
    ]
    KhalaTodayView(
        timeline: KhalaTimeline.build(
            entities: [sun],
            devices: devices,
            automationConfigs: [:],
            now: now,
            calendar: calendar
        ),
        now: now,
        calendar: calendar,
        onMenu: {},
        onSearch: {},
        onItem: { _ in },
        onDevice: { _ in }
    )
    .background(KhalaGround())
}
