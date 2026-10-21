import SFSafeSymbols
import Shared
import SwiftUI
import UIKit

/// One camera's screen (mockups `DayCamera` / `DayCameraPicker`). The title is a pull-down of every camera; Live
/// hosts the app's own native player in a card (full screen opens the app's camera overlay) with Snapshot and — when
/// the camera has a notifications switch — Mute; then "Today on <camera>" from its event entities. Events lists its
/// detections of the last week (recorder history); Settings shows what Home Assistant says about it. A detection
/// shows the still the home saved for it (`KhalaCaptureSource`); a tap opens it full screen, never the stream.
struct KhalaCameraView: View {
    let cameraEntityId: String
    let server: Server
    @ObservedObject var live: KhalaLiveStates
    let actions: KhalaScreenActions
    let now: Date
    let calendar: Calendar
    let onSelectCamera: (String) -> Void
    let onAllCameras: () -> Void
    let onFullScreen: (String, String?) -> Void
    /// A detection's capture, full screen (`KhalaShellModel.openCapture`).
    let onCapture: (KhalaEntity, Date) -> Void

    @State private var tab = 0
    @State private var showsPicker = false
    @State private var history: [String: [KhalaHistoryState]]? = nil
    @State private var snapshot: KhalaSnapshot? = nil
    @State private var snapshotFailed = false
    /// The player the live card settled on (WebRTC first when the camera offers it, `CameraStreamPlan`).
    @State private var livePlayer: CameraPlayerType?

    private static let tabs = [
        KhalaSubTab(title: KhalaScreenText.live, symbol: .videoFill),
        KhalaSubTab(title: KhalaScreenText.events, symbol: .listBullet),
        KhalaSubTab(title: KhalaScreenText.settings, symbol: .gearshape),
    ]

    var body: some View {
        let camera = live.entitiesById[cameraEntityId]
        let cameras = KhalaDeviceCatalog.cameras(in: live.entities)
        let startOfToday = calendar.startOfDay(for: now)
        let today = camera.map {
            KhalaCameraCatalog.detections(for: $0, in: live.entities, history: history ?? [:], since: startOfToday, now: now)
        } ?? []
        ZStack(alignment: .topLeading) {
            KhalaDeviceScreen(
                subtitle: KhalaCameraCatalog.subtitle(detectionsToday: today.count),
                tabs: Self.tabs,
                selection: $tab,
                category: .security,
                title: { titleButton(camera?.name ?? cameraEntityId, hasChoice: cameras.count > 1) },
                trailing: { EmptyView() },
                content: {
                    if let camera {
                        switch tab {
                        case 1: events(camera)
                        case 2: settings(camera)
                        default: liveTab(camera, today: today)
                        }
                    } else {
                        Text(KhalaScreenText.unknownDevice)
                            .font(KhalaTheme.body)
                            .foregroundStyle(KhalaTheme.secondary)
                    }
                }
            )
            if showsPicker {
                KhalaCameraPicker(
                    rows: KhalaCameraCatalog.rows(cameras: cameras, entities: live.entities, now: now, calendar: calendar),
                    selectedId: cameraEntityId,
                    onAllCameras: {
                        showsPicker = false
                        onAllCameras()
                    },
                    onSelect: { entityId in
                        showsPicker = false
                        onSelectCamera(entityId)
                    },
                    onDismiss: { showsPicker = false }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: showsPicker)
        .task(id: cameraEntityId) {
            history = nil
            guard let camera else { return }
            let events = KhalaCameraCatalog.eventEntities(for: camera, in: live.entities).map(\.entityId)
            history = await actions.history(entityIds: events, since: Current.date().addingTimeInterval(-7 * 86400))
        }
        .sheet(item: $snapshot) { snapshot in
            KhalaSnapshotSheet(snapshot: snapshot)
        }
        .alert(KhalaScreenText.snapshotFailed, isPresented: $snapshotFailed) {
            Button(KhalaScreenText.close, role: .cancel) {}
        }
    }

    // MARK: - Title

    private func titleButton(_ name: String, hasChoice: Bool) -> some View {
        Button {
            showsPicker.toggle()
        } label: {
            HStack(spacing: 8) {
                KhalaLargeTitle(text: name)
                Image(systemSymbol: .chevronDown)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(KhalaTheme.accent(.security))
                    .frame(width: 26, height: 26)
                    .background(KhalaTheme.tint(.security), in: Circle())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(KhalaScreenText.chooseCamera)")
        .accessibilityHint(hasChoice ? KhalaScreenText.chooseCamera : "")
    }

    // MARK: - Live

    @ViewBuilder
    private func liveTab(_ camera: KhalaEntity, today: [KhalaDetection]) -> some View {
        let mute = KhalaCameraCatalog.notificationSwitch(for: camera, in: live.entities)
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                KhalaCameraLivePlayer(
                    server: server,
                    cameraEntityId: camera.entityId,
                    cameraName: camera.name,
                    poster: { await actions.thumbnail(cameraEntityId: camera.entityId) },
                    onPlayer: { livePlayer = $0 }
                )
                .id(camera.entityId)
                badge {
                    HStack(spacing: 6) {
                        Circle().fill(Color(red: 0.847, green: 0.278, blue: 0.231)).frame(width: 6, height: 6)
                        // "LIVE · WEBRTC": which player is on, so a laggy stream can be told from a fallback.
                        Text(([KhalaScreenText.live] + (livePlayer.map { [Self.playerName($0)] } ?? []))
                            .joined(separator: " · ").uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .kerning(0.8)
                    }
                }
                .padding(10)
                .allowsHitTesting(false)
                Button {
                    onFullScreen(camera.entityId, camera.name)
                } label: {
                    badge {
                        Image(systemSymbol: .arrowUpLeftAndArrowDownRight)
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KhalaScreenText.fullScreen)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(10)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            HStack(spacing: 8) {
                actionButton(KhalaScreenText.snapshot, symbol: .cameraFill) {
                    Task {
                        if let image = await actions.snapshot(cameraEntityId: camera.entityId) {
                            snapshot = KhalaSnapshot(image: image, cameraName: camera.name)
                        } else {
                            snapshotFailed = true
                        }
                    }
                }
                if let mute {
                    let muted = mute.state == "off"
                    actionButton(muted ? KhalaScreenText.unmute : KhalaScreenText.mute,
                                 symbol: muted ? .bellFill : .bellSlashFill) {
                        Task { await actions.perform(KhalaServiceCall.power(mute.entityId, on: muted)) }
                    }
                }
            }
        }
        .padding(8)
        .background(KhalaTheme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .khalaCardShadow()

        KhalaSectionHeader(title: KhalaScreenText.todayOn(camera.name))
        todayTimeline(camera, today: today)
    }

    private static func playerName(_ player: CameraPlayerType) -> String {
        switch player {
        case .webRTC: return "WebRTC"
        case .hls: return "HLS"
        case .mjpeg: return "MJPEG"
        }
    }

    private func badge<BadgeContent: View>(@ViewBuilder _ label: () -> BadgeContent) -> some View {
        label()
            .foregroundStyle(KhalaTheme.ink)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color.white.opacity(0.78), in: Capsule())
    }

    private func actionButton(_ title: String, symbol: SFSymbol, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemSymbol: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KhalaTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(KhalaTheme.groundFlat, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Today's detections above Now, then the camera's own clock-driven automations below it.
    @ViewBuilder
    private func todayTimeline(_ camera: KhalaEntity, today: [KhalaDetection]) -> some View {
        let past = Array(today.prefix(KhalaTimeline.maximumDetections).reversed())
        let memberIds = Set(live.entities.filter { $0.deviceId != nil && $0.deviceId == camera.deviceId }.map(\.entityId))
            .union([camera.entityId])
        let upcoming = KhalaDeviceAutomations.related(
            to: memberIds, configs: live.automationConfigs, entities: live.entities, now: now,
            horizon: calendar.startOfDay(for: now).addingTimeInterval(86400 + KhalaTimeline.upcomingGrace)
                .timeIntervalSince(now),
            calendar: calendar
        ).filter { !$0.fireDates.isEmpty }
        VStack(spacing: 0) {
            ForEach(Array(past.enumerated()), id: \.element.id) { index, detection in
                KhalaTimelineRow(
                    time: KhalaText.time(detection.date, calendar: calendar),
                    isNow: false,
                    dot: .past(.security),
                    dotCenter: KhalaEventCard.height / 2,
                    lineAbove: index == 0 ? nil : KhalaTheme.ink,
                    lineBelow: KhalaTheme.ink
                ) {
                    KhalaEventCard(
                        title: detection.noun,
                        subtitle: detection.source,
                        category: .security,
                        capture: KhalaCaptureRef(cameraEntityId: camera.entityId, date: detection.date)
                    ) {
                        onCapture(camera, detection.date)
                    }
                }
            }
            KhalaPlainTimelineRow(
                time: KhalaText.now,
                text: KhalaScreenText.watching,
                detail: today.isEmpty ? KhalaText.allClear : KhalaText.detections(today.count),
                dot: .now,
                lineAbove: past.isEmpty ? nil : KhalaTheme.ink,
                lineBelow: upcoming.isEmpty ? nil : KhalaTheme.line,
                isNow: true
            )
            ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, automation in
                KhalaPlainTimelineRow(
                    time: automation.fireDates.first.map { KhalaText.time($0, calendar: calendar) } ?? "",
                    text: automation.name,
                    detail: nil,
                    dot: .upcoming(.security),
                    lineAbove: KhalaTheme.line,
                    lineBelow: index == upcoming.count - 1 ? nil : KhalaTheme.line
                )
            }
        }
    }

    // MARK: - Events

    @ViewBuilder
    private func events(_ camera: KhalaEntity) -> some View {
        if let history {
            let week = KhalaCameraCatalog.detections(
                for: camera, in: live.entities, history: history,
                since: Current.date().addingTimeInterval(-7 * 86400), now: now
            )
            if week.isEmpty {
                Text(KhalaScreenText.noDetectionsYet)
                    .font(KhalaTheme.body)
                    .foregroundStyle(KhalaTheme.secondary)
                    .khalaCard()
            } else {
                let days = Dictionary(grouping: week) { calendar.startOfDay(for: $0.date) }
                ForEach(days.keys.sorted(by: >), id: \.self) { day in
                    Text(dayTitle(day))
                        .font(KhalaTheme.caption)
                        .kerning(1)
                        .foregroundStyle(KhalaTheme.muted)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                    VStack(spacing: 0) {
                        let items = days[day] ?? []
                        ForEach(items) { detection in
                            Button {
                                onCapture(camera, detection.date)
                            } label: {
                                HStack(spacing: 12) {
                                    KhalaCaptureThumbnail(
                                        ref: KhalaCaptureRef(cameraEntityId: camera.entityId, date: detection.date),
                                        category: .security,
                                        cornerRadius: 10
                                    )
                                    .frame(width: 56, height: 42)
                                    Text(KhalaText.time(detection.date, calendar: calendar))
                                        .font(KhalaTheme.time)
                                        .foregroundStyle(KhalaTheme.muted)
                                        .frame(width: KhalaTheme.timeColumn, alignment: .leading)
                                    Text(detection.noun)
                                        .font(KhalaTheme.cardTitle)
                                        .foregroundStyle(KhalaTheme.ink)
                                    Text(detection.source)
                                        .font(KhalaTheme.secondaryText)
                                        .foregroundStyle(KhalaTheme.tertiary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            if detection.id != items.last?.id { Divider() }
                        }
                    }
                    .khalaCard(padding: 14, radius: 22)
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }

    private func dayTitle(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return KhalaText.today.uppercased() }
        if calendar.isDateInYesterday(day) { return KhalaScreenText.yesterday.uppercased() }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: day).uppercased()
    }

    // MARK: - Settings

    @ViewBuilder
    private func settings(_ camera: KhalaEntity) -> some View {
        let attributes = live.attributes[camera.entityId] ?? [:]
        VStack(spacing: 0) {
            KhalaInfoRow(title: KhalaScreenText.entityId, value: camera.entityId)
            Divider()
            KhalaInfoRow(title: KhalaScreenText.state, value: KhalaText.humanized(state: camera.state))
            Divider()
            KhalaInfoRow(
                title: KhalaScreenText.stream,
                value: KhalaCameraCatalog.supportsStream(attributes: attributes) ? KhalaScreenText.on : KhalaScreenText.stillsOnly
            )
            Divider()
            KhalaInfoRow(title: KhalaScreenText.lastChanged, value: KhalaText.time(camera.lastChanged, calendar: calendar))
            if let model = camera.deviceId.flatMap({ live.deviceModels[$0] }) {
                Divider()
                KhalaInfoRow(title: KhalaScreenText.model, value: model)
            }
        }
        .khalaCard(padding: 16)

        let events = KhalaCameraCatalog.eventEntities(for: camera, in: live.entities)
        if !events.isEmpty {
            KhalaSectionHeader(title: KhalaScreenText.detectionSources)
            VStack(spacing: 0) {
                ForEach(events, id: \.entityId) { event in
                    KhalaInfoRow(
                        title: KhalaCameraCatalog.sourceName(event, camera: camera),
                        value: event.stateDate.map { KhalaText.time($0, calendar: calendar) } ?? KhalaText.humanized(state: event.state)
                    )
                    if event.entityId != events.last?.entityId { Divider() }
                }
            }
            .khalaCard(padding: 16)
        }

        let shown = KhalaAttributeText.rows(attributes)
        if !shown.isEmpty {
            KhalaSectionHeader(title: KhalaScreenText.attributes)
            VStack(spacing: 0) {
                ForEach(shown, id: \.key) { row in
                    KhalaInfoRow(title: row.key, value: row.value)
                    if row.key != shown.last?.key { Divider() }
                }
            }
            .khalaCard(padding: 16)
        }
    }
}
