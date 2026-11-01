import Foundation
@testable import HomeAssistant
import Testing

/// How a capture's instant is read from its snapshot path (`<day folder>/<HHMMSS>_<camera>.jpg`) in the server's
/// time zone, including the days a zone changes its clocks. The zones are generic IANA ones, not the home's.
struct KhalaCaptureDateTests {
    private static let config = KhalaCaptureConfig.standard
    private static let newYork = TimeZone(identifier: "America/New_York")!
    private static let plusThree = TimeZone(secondsFromGMT: 3 * 3600)!

    private static func date(_ string: String) -> Date { KhalaDateParser.timestamp(string)! }

    private static func file(_ name: String, folder: Bool = false) -> KhalaMediaNode {
        KhalaMediaNode(title: name, mediaContentId: "media-source://media_source/caps/day/" + name, canExpand: folder)
    }

    private static func captures(_ names: [String], day folder: String, zone: TimeZone,
                                 config: KhalaCaptureConfig = config) -> [KhalaCapture] {
        guard let day = KhalaCaptureIndex.day(ofFolder: folder, config: config, timeZone: zone) else { return [] }
        return KhalaCaptureIndex.captures(in: names.map { file($0) }, day: day, config: config, timeZone: zone)
    }

    @Test func aDayFolderStartsAtTheServersMidnight() {
        #expect(KhalaCaptureIndex.day(ofFolder: "2026-03-08", config: Self.config, timeZone: Self.newYork)
            == Self.date("2026-03-08T05:00:00Z"))
        #expect(KhalaCaptureIndex.day(ofFolder: "2026-07-01", config: Self.config, timeZone: Self.newYork)
            == Self.date("2026-07-01T04:00:00Z"))
        #expect(KhalaCaptureIndex.day(ofFolder: "2026-10-21", config: Self.config, timeZone: Self.plusThree)
            == Self.date("2026-10-20T21:00:00Z"))
    }

    @Test func folderNamesMustBeExactlyTheFormat() {
        for name in ["2026-3-8", "2026-03-8", "26-03-08", "2026/03/08", "2026-02-30", "", "snapshots"] {
            #expect(KhalaCaptureIndex.day(ofFolder: name, config: Self.config, timeZone: Self.newYork) == nil)
        }
    }

    @Test func theDayFolderOfAnInstantIsTheServersDate() {
        #expect(KhalaCaptureIndex.dayFolder(for: Self.date("2026-03-08T04:59:59Z"), config: Self.config,
                                            timeZone: Self.newYork) == "2026-03-07")
        #expect(KhalaCaptureIndex.dayFolder(for: Self.date("2026-03-08T05:00:00Z"), config: Self.config,
                                            timeZone: Self.newYork) == "2026-03-08")
        #expect(KhalaCaptureIndex.dayFolder(for: Self.date("2026-10-20T20:59:59Z"), config: Self.config,
                                            timeZone: Self.plusThree) == "2026-10-20")
    }

    @Test func fileTimesAreTheServersLocalTimeOnEitherSideOfAClockChange() {
        // Spring forward (02:00 → 03:00 local): before it UTC−5, after it UTC−4.
        let spring = Self.captures(["013000_porch.jpg", "033000_porch.jpg"], day: "2026-03-08", zone: Self.newYork)
        #expect(spring.map(\.date) == [Self.date("2026-03-08T06:30:00Z"), Self.date("2026-03-08T07:30:00Z")])
        // Fall back (02:00 → 01:00 local): before it UTC−4, after it UTC−5.
        let fall = Self.captures(["003000_porch.jpg", "023000_porch.jpg"], day: "2026-11-01", zone: Self.newYork)
        #expect(fall.map(\.date) == [Self.date("2026-11-01T04:30:00Z"), Self.date("2026-11-01T07:30:00Z")])
    }

    @Test func theSameFileNameIsADifferentInstantInAnotherZone() {
        let east = Self.captures(["120000_porch.jpg"], day: "2026-10-21", zone: Self.plusThree)
        let west = Self.captures(["120000_porch.jpg"], day: "2026-10-21", zone: Self.newYork)
        #expect(east.first?.date == Self.date("2026-10-21T09:00:00Z"))
        #expect(west.first?.date == Self.date("2026-10-21T16:00:00Z"))
    }

    @Test func namesAndExtensionsThatCountAndOnesThatDont() {
        let captures = Self.captures([
            "235959_Back_Yard.JPG", "000000_porch.jpeg", "101010_gate_2.png", "101010_gate.gif", "240000_porch.jpg",
            "126000_porch.jpg", "120060_porch.jpg", "12000_porch.jpg", "120000-porch.jpg", "120000_porch.jpg.tmp",
            "120000_.jpg", "x120000_porch.jpg",
        ], day: "2026-10-21", zone: Self.plusThree)
        // Oldest first; the camera part is lower-cased to match entity object ids.
        #expect(captures.map(\.cameraObjectId) == ["porch", "gate_2", "back_yard"])
        #expect(captures.map(\.date) == [
            Self.date("2026-10-20T21:00:00Z"), Self.date("2026-10-21T07:10:10Z"), Self.date("2026-10-21T20:59:59Z"),
        ])
    }

    @Test func foldersAreNeverCaptures() {
        let day = KhalaCaptureIndex.day(ofFolder: "2026-10-21", config: Self.config, timeZone: Self.plusThree)!
        let nodes = [Self.file("120000_porch.jpg", folder: true), Self.file("120001_porch.jpg")]
        let captures = KhalaCaptureIndex.captures(in: nodes, day: day, config: Self.config, timeZone: Self.plusThree)
        #expect(captures.map(\.mediaContentId) == ["media-source://media_source/caps/day/120001_porch.jpg"])
    }

    @Test func anotherLayoutIsJustData() {
        let compact = KhalaCaptureConfig(
            rootId: "media-source://media_source/cam",
            dayFolderFormat: "yyyyMMdd",
            filePattern: #"^([a-z0-9_]+)-([0-9]{6})\.jpg$"#,
            matchWindow: 30
        )
        #expect(KhalaCaptureIndex.dayFolder(for: Self.date("2026-10-21T09:00:00Z"), config: compact,
                                            timeZone: Self.plusThree) == "20261021")
        // Group 1 is always the time and group 2 the camera: a pattern with them the other way round finds nothing.
        #expect(Self.captures(["porch-120000.jpg"], day: "20261021", zone: Self.plusThree, config: compact).isEmpty)
        let swapped = KhalaCaptureConfig(rootId: nil, dayFolderFormat: "yyyyMMdd",
                                         filePattern: #"^([0-9]{6})-([a-z0-9_]+)\.jpg$"#, matchWindow: 30)
        let found = Self.captures(["120000-porch.jpg"], day: "20261021", zone: Self.plusThree, config: swapped)
        #expect(found.first?.date == Self.date("2026-10-21T09:00:00Z"))
        #expect(found.first?.cameraObjectId == "porch")
    }

    @Test func aBrokenPatternFindsNothingInsteadOfCrashing() {
        let broken = KhalaCaptureConfig(rootId: nil, dayFolderFormat: "yyyy-MM-dd", filePattern: "([0-9", matchWindow: 90)
        #expect(Self.captures(["120000_porch.jpg"], day: "2026-10-21", zone: Self.plusThree, config: broken).isEmpty)
    }

    @Test func matchingUsesTheWindowOnBothSidesAndTheExactCamera() {
        let captures = Self.captures(["120000_porch.jpg", "120000_porch_2.jpg"], day: "2026-10-21", zone: Self.plusThree)
        let at = Self.date("2026-10-21T09:00:00Z")
        let config = Self.config
        #expect(KhalaCaptureIndex.match(cameraEntityId: "camera.porch", date: at.addingTimeInterval(-90),
                                        in: captures, config: config)?.cameraObjectId == "porch")
        #expect(KhalaCaptureIndex.match(cameraEntityId: "camera.porch", date: at.addingTimeInterval(90),
                                        in: captures, config: config) != nil)
        #expect(KhalaCaptureIndex.match(cameraEntityId: "camera.porch", date: at.addingTimeInterval(91),
                                        in: captures, config: config) == nil)
        #expect(KhalaCaptureIndex.match(cameraEntityId: "camera.Porch_2", date: at, in: captures,
                                        config: config)?.cameraObjectId == "porch_2")
        #expect(KhalaCaptureIndex.match(cameraEntityId: "camera.yard", date: at, in: captures, config: config) == nil)
    }
}
