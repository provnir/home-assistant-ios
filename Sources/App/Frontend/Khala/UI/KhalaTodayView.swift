import SFSafeSymbols
import SwiftUI

/// Today: the home's day as a vertical timeline (mockup `DayHome`), newest on top (Nir, build 24.1): upcoming above
/// "Now", the past below it, and the screen opens on Now (`KhalaNowScrollView`). The Now card holds live device chips. A floating glass button opens the menu's search (the menu button itself is pinned by
/// the shell); everything else is solid. The ground is drawn by the shell, masked to the card's shape.
struct KhalaTodayView: View {
    let timeline: KhalaTimeline
    let now: Date
    let calendar: Calendar
    /// Kept for call-site compatibility; the shell owns the menu button now.
    let onMenu: () -> Void
    let onSearch: () -> Void
    let onItem: (KhalaTimelineItem) -> Void
    let onDevice: (KhalaDevice) -> Void
    /// Bumped by the shell when Today is chosen again in the drawer: back to Now.
    var scrollRequest = 0

    /// Bumped by a tap on the title: back to Now.
    @State private var titleTaps = 0

    /// Where Now's top settles: just under the floating menu/search buttons.
    private static let nowInset: CGFloat = 9 + 44 + 4

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter
    }()

    /// The capture a detection card shows: its camera's, at its time.
    static func captureRef(_ item: KhalaTimelineItem) -> KhalaCaptureRef? {
        guard case let .detection(_, cameraEntityId) = item.kind, let cameraEntityId else { return nil }
        return KhalaCaptureRef(cameraEntityId: cameraEntityId, date: item.date)
    }

    var body: some View {
        ZStack(alignment: .top) {
            KhalaNowScrollView(idsAboveNow: timeline.idsAboveNow, request: scrollRequest + titleTaps) {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        titleTaps += 1
                    } label: {
                        Text(KhalaText.today)
                            .font(KhalaTheme.largeTitle)
                            .kerning(0.3)
                            .foregroundStyle(KhalaTheme.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHint(KhalaText.backToNow)
                    Text(verbatim: "\(Self.dateFormatter.string(from: now)) · \(timeline.summary)")
                        .font(KhalaTheme.headerSubtitle)
                        .foregroundStyle(KhalaTheme.secondary)
                        .padding(.top, 1)
                        .padding(.bottom, 26)

                    let items = timeline.items
                    let strokes = timeline.strokes
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        // The light line through what's coming, ink from Now down through the past.
                        let lineAbove = KhalaTheme.stroke(strokes[index].above)
                        let lineBelow = KhalaTheme.stroke(strokes[index].below)
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
                            KhalaNowMarker(inset: Self.nowInset)
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
                                KhalaEventCard(
                                    title: item.title,
                                    subtitle: item.subtitle,
                                    category: item.category,
                                    capture: Self.captureRef(item)
                                ) {
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
                // Room for the floating buttons above the title, and below the earliest row.
                .padding(.top, Self.nowInset)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)

            // The menu button is the shell's, pinned top-leading over every screen; search stays Today's own.
            HStack {
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
