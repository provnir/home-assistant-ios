import Foundation
@testable import HomeAssistant
import Testing

/// Build 19.1 feedback: floating sub-tabs, the lens across a tab switch, car refresh, detection captures.
/// Synthetic names only ("Rover", "porch", "yard").
private enum Polish {
    static let zone = TimeZone(identifier: "Asia/Jerusalem")!
    static let config = KhalaCaptureConfig.standard

    static func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text)!
    }

    static func file(_ day: String, _ name: String) -> KhalaMediaNode {
        KhalaMediaNode(title: name, mediaContentId: "media-source://media_source/caps/\(day)/\(name)", canExpand: false)
    }

    static func entity(_ id: String, updated: Date) -> KhalaEntity {
        KhalaEntity(entityId: id, state: "on", lastChanged: updated.addingTimeInterval(-600), attributes: [:],
                    lastUpdated: updated, deviceId: "rover")
    }
}

struct KhalaSubTabMetricsTests {
    @Test func theBarHugsItsTabsAndKeepsItsMargins() {
        // Three tabs on a 390 pt phone: preferred width, a 250 pt capsule, far from the edges.
        let three = KhalaSubTabMetrics.tabWidth(available: 390, count: 3)
        #expect(three == 80)
        #expect(KhalaSubTabMetrics.barWidth(tabWidth: three, count: 3) == 250)
        // Four tabs still fit at the preferred width (330 + 2 × 24 ≤ 390).
        #expect(KhalaSubTabMetrics.tabWidth(available: 390, count: 4) == 80)
        // Six tabs shrink to keep 24 pt each side, never below the minimum.
        let six = KhalaSubTabMetrics.tabWidth(available: 390, count: 6)
        #expect(KhalaSubTabMetrics.barWidth(tabWidth: six, count: 6) <= 390 - 48 + 0.001)
        #expect(KhalaSubTabMetrics.tabWidth(available: 200, count: 6) == KhalaSubTabMetrics.minimumTabWidth)
    }

    @Test func theLensSitsUnderTheSelectedTabAndClamps() {
        #expect(KhalaSubTabMetrics.lensOffset(selection: 0, count: 3, tabWidth: 80) == 5)
        #expect(KhalaSubTabMetrics.lensOffset(selection: 2, count: 3, tabWidth: 80) == 165)
        #expect(KhalaSubTabMetrics.lensOffset(selection: 7, count: 3, tabWidth: 80) == 165)
        #expect(KhalaSubTabMetrics.lensOffset(selection: -1, count: 3, tabWidth: 80) == 5)
    }
}

struct KhalaPageTabHoldTests {
    private static func header(active: Int) -> KhalaPageHeader {
        let paths = ["/config/integrations", "/config/devices", "/config/entities"]
        let state = KhalaFrontendState(
            path: paths[active] + "/dashboard",
            page: KhalaPageChrome(
                kind: .tabs,
                title: "Devices",
                hasBack: true,
                tabs: paths.enumerated().map { KhalaPageTab(path: $1, title: $1, isActive: $0 == active) }
            )
        )
        return KhalaPageHeader(
            path: state.path, state: state, isMoreInfoOpen: false, settingsEntryPath: nil, fallbackTitle: "Settings"
        )!
    }

    @Test func theChromeStaysUpWithTheChosenTabWhileTheNextPageLoads() {
        let now = Date(timeIntervalSince1970: 1000)
        let hold = KhalaPageTabHold(header: Self.header(active: 0), selecting: "/config/devices", now: now)
        #expect(hold != nil)
        // The frontend reports no page between the two tabs: the held header answers, the new tab active.
        let held = hold?.header(fresh: nil, now: now.addingTimeInterval(0.3))
        #expect(held?.activeTabIndex == 1)
        #expect(held?.tabs.count == 3)
        // The new page's own report wins as soon as it arrives.
        #expect(hold?.header(fresh: Self.header(active: 1), now: now.addingTimeInterval(0.5)) == Self.header(active: 1))
        // A page that never reports doesn't keep stale chrome up.
        #expect(hold?.header(fresh: nil, now: now.addingTimeInterval(KhalaPageTabHold.duration + 0.1)) == nil)
    }

    @Test func nothingToHoldWithoutChromeOrForAnotherPage() {
        #expect(KhalaPageTabHold(header: nil, selecting: "/config/devices", now: Date()) == nil)
        #expect(KhalaPageTabHold(header: Self.header(active: 0), selecting: "/config/areas", now: Date()) == nil)
    }
}

struct KhalaEntityRefreshTests {
    @Test func oneCallNamesWhatReportsNotButtons() {
        let now = Date(timeIntervalSince1970: 50000)
        let members = [
            Polish.entity("sensor.rover_battery", updated: now),
            Polish.entity("button.rover_wake", updated: now),
            Polish.entity("button.rover_honk", updated: now),
            Polish.entity("device_tracker.rover_location", updated: now),
            Polish.entity("update.rover_update", updated: now),
            Polish.entity("lock.rover_lock", updated: now),
        ]
        let ids = KhalaEntityRefresh.entityIds(of: members)
        #expect(ids == ["device_tracker.rover_location", "lock.rover_lock", "sensor.rover_battery"])
        #expect(!ids.contains { $0.hasPrefix("button.") })
        let call = KhalaServiceCall.updateEntities(ids)
        #expect(call.name == "homeassistant.update_entity")
        #expect(call.data["entity_id"] as? [String] == ids)
    }

    @Test func freshnessIsTheNewestReportNotTheLastButtonPress() {
        let old = Date(timeIntervalSince1970: 10000)
        let pressed = Date(timeIntervalSince1970: 90000)
        let members = [
            Polish.entity("sensor.rover_battery", updated: old),
            Polish.entity("sensor.rover_range", updated: old.addingTimeInterval(60)),
            Polish.entity("button.rover_wake", updated: pressed),
        ]
        #expect(KhalaEntityRefresh.lastUpdated(of: members) == old.addingTimeInterval(60))
        #expect(KhalaScreenText.updated(old, now: old.addingTimeInterval(30)) == "Updated just now")
        #expect(KhalaScreenText.updated(old, now: old.addingTimeInterval(4 * 60 + 5)) == "Updated 4 min ago")
        #expect(KhalaScreenText.updated(old, now: old.addingTimeInterval(3 * 3600)) == "Updated 3 h ago")
        #expect(KhalaScreenText.updated(old, now: old.addingTimeInterval(2 * 86400)) == "Updated 2 d ago")
    }

    @Test func lastUpdatedDefaultsToLastChanged() {
        let changed = Date(timeIntervalSince1970: 1234)
        let entity = KhalaEntity(entityId: "sensor.x", state: "1", lastChanged: changed, attributes: [:])
        #expect(entity.lastUpdated == changed)
    }

    @Test func openingTheScreenAgainSoonDoesntWakeAndReadTwice() {
        var throttle = KhalaRefreshThrottle()
        let start = Date(timeIntervalSince1970: 0)
        #expect(throttle.allowsAutomatic("rover", now: start))
        let began = throttle.begin("rover")
        #expect(began)
        // Never two at once, explicit or not.
        let again = throttle.begin("rover")
        #expect(!again)
        #expect(!throttle.allowsAutomatic("rover", now: start.addingTimeInterval(5)))
        throttle.finish("rover", now: start.addingTimeInterval(20), completed: true)
        // Within a minute of the completed read: the screen opening doesn't refresh; another car isn't held back.
        #expect(!throttle.allowsAutomatic("rover", now: start.addingTimeInterval(70)))
        #expect(throttle.allowsAutomatic("tank", now: start.addingTimeInterval(70)))
        // "Refresh now" always runs (it only needs nothing running).
        let explicit = throttle.begin("rover")
        #expect(explicit)
        throttle.finish("rover", now: start.addingTimeInterval(90), completed: false)
        // A failed run (the car didn't wake) doesn't hold the next automatic one back.
        #expect(throttle.allowsAutomatic("rover", now: start.addingTimeInterval(95)))
        #expect(throttle.allowsAutomatic("rover", now: start.addingTimeInterval(20 + 60)))
    }
}

struct KhalaCaptureTests {
    @Test func dayFoldersAreFoundAndJunkSkipped() {
        let root = [
            KhalaMediaNode(title: "2026-10-20", mediaContentId: "media-source://media_source/caps/2026-10-20", canExpand: true),
            KhalaMediaNode(title: "porch_20261019-152452.jpg", mediaContentId: "x", canExpand: false),
        ]
        #expect(KhalaCaptureIndex.looksLikeCaptureRoot(root, config: Polish.config, timeZone: Polish.zone))
        let notCaptures = [KhalaMediaNode(title: "music", mediaContentId: "m", canExpand: true)]
        #expect(!KhalaCaptureIndex.looksLikeCaptureRoot(notCaptures, config: Polish.config, timeZone: Polish.zone))
        #expect(KhalaCaptureIndex.day(ofFolder: "2026-13-40", config: Polish.config, timeZone: Polish.zone) == nil)
        // The folder is the day folders' parent, wherever the media dir sits.
        #expect(KhalaCaptureIndex.root(of: root, config: Polish.config, timeZone: Polish.zone)
            == "media-source://media_source/caps")
        #expect(KhalaCaptureIndex.root(of: notCaptures, config: Polish.config, timeZone: Polish.zone) == nil)
        #expect(KhalaCaptureIndex.parentId(of: "media-source://media_source") == "media-source://media_source")
        #expect(KhalaCaptureIndex.lastComponent(of: "media-source://media_source/caps/2026-10-21") == "2026-10-21")

        let day = KhalaCaptureIndex.day(ofFolder: "2026-10-21", config: Polish.config, timeZone: Polish.zone)!
        let files = [
            Polish.file("2026-10-21", "083533_porch.jpg"),
            Polish.file("2026-10-21", "test_yard.jpg"),
            Polish.file("2026-10-21", "porch_20261021-152452.jpg"),
            Polish.file("2026-10-21", "251000_porch.jpg"),
            Polish.file("2026-10-21", "120000_back_yard_2.JPG"),
        ]
        let captures = KhalaCaptureIndex.captures(in: files, day: day, config: Polish.config, timeZone: Polish.zone)
        #expect(captures.map(\.cameraObjectId) == ["porch", "back_yard_2"])
        // File times are the server's local time (UTC+3 on this date).
        #expect(captures.first?.date == Polish.date("2026-10-21T05:35:33Z"))
    }

    @Test func dayFolderOfADateIsTheServersDay() {
        // 22:30 UTC on the 20th is already the 21st in the server's zone.
        let date = Polish.date("2026-10-20T22:30:00Z")
        #expect(KhalaCaptureIndex.dayFolder(for: date, config: Polish.config, timeZone: Polish.zone) == "2026-10-21")
        #expect(KhalaCaptureIndex.dayFolderId(rootId: "media-source://media_source/caps", date: date,
                                              config: Polish.config, timeZone: Polish.zone)
            == "media-source://media_source/caps/2026-10-21")
    }

    @Test func aDetectionMatchesItsCamerasNearestCaptureWithinTheWindow() {
        let day = KhalaCaptureIndex.day(ofFolder: "2026-10-21", config: Polish.config, timeZone: Polish.zone)!
        let captures = KhalaCaptureIndex.captures(in: [
            Polish.file("2026-10-21", "083500_porch.jpg"),
            Polish.file("2026-10-21", "083540_porch.jpg"),
            Polish.file("2026-10-21", "083530_yard.jpg"),
        ], day: day, config: Polish.config, timeZone: Polish.zone)
        // Detection at 08:35:30 local on the porch: 08:35:40 is nearer than 08:35:00; the yard's is another camera.
        let detection = Polish.date("2026-10-21T05:35:30Z")
        let match = KhalaCaptureIndex.match(cameraEntityId: "camera.porch", date: detection, in: captures, config: Polish.config)
        #expect(match?.mediaContentId.hasSuffix("083540_porch.jpg") == true)
        // Two minutes off: no capture.
        let late = detection.addingTimeInterval(200)
        #expect(KhalaCaptureIndex.match(cameraEntityId: "camera.porch", date: late, in: captures, config: Polish.config) == nil)
        #expect(KhalaCaptureIndex.objectId(of: "camera.back_yard_2") == "back_yard_2")
    }

    @Test func browseAnswersParse() {
        let response: [String: Any] = ["children": [
            ["title": "2026-10-21", "media_content_id": "media-source://media_source/caps/2026-10-21", "can_expand": true],
            ["title": "083533_porch.jpg", "media_content_id": "media-source://media_source/caps/2026-10-21/083533_porch.jpg",
             "can_expand": false],
            ["title": "no id"],
        ]]
        let nodes = KhalaMediaNode.children(of: response)
        #expect(nodes.count == 2)
        #expect(nodes.first?.canExpand == true)
    }
}

struct KhalaCarWakePlanTests {
    private static func layout(_ change: (inout [KhalaEntity]) -> Void) -> KhalaCarLayout {
        var members = KhalaScreenFixtures.car
        change(&members)
        return KhalaCarLayout(name: "Rover", members: members, attributes: KhalaScreenFixtures.carAttributes)
    }

    private static func status(_ state: String) -> KhalaEntity {
        KhalaScreenFixtures.entity("binary_sensor.rover_status", state, ["device_class": "connectivity"],
                                   device: "rover", deviceName: "Rover")
    }

    @Test func aRefreshWakesAnAsleepOrOfflineCarAndWaits() {
        let asleep = Self.layout { _ in }
        #expect(asleep.wakePlan == .pressAndWait(button: "button.rover_wake", connectivity: "binary_sensor.rover_status"))
        // Offline (an unavailable sensor) wakes and waits too.
        let offline = Self.layout { members in
            members.removeAll { $0.entityId == "binary_sensor.rover_status" }
            members.append(Self.status("unavailable"))
        }
        #expect(offline.wakePlan == .pressAndWait(button: "button.rover_wake", connectivity: "binary_sensor.rover_status"))
    }

    @Test func anAwakeCarIsReadStraightAway() {
        let awake = Self.layout { members in
            members.removeAll { $0.entityId == "binary_sensor.rover_status" }
            members.append(Self.status("on"))
        }
        #expect(awake.wakePlan == .none)
        let noButton = Self.layout { $0.removeAll { $0.entityId == "button.rover_wake" } }
        #expect(noButton.wakePlan == .none)
        // A wake button but no sensor to wait on: press it, then read.
        let noSensor = Self.layout { $0.removeAll { $0.entityId == "binary_sensor.rover_status" } }
        #expect(noSensor.wakePlan == .press(button: "button.rover_wake"))
    }
}
