import Foundation
@testable import HomeAssistant
import Testing

struct KhalaParsingTests {
    @Test(arguments: [
        ("2026-10-21T03:48:30.681916+00:00", 1_792_554_510.681916),
        ("2026-10-20T07:16:32.953+00:00", 1_792_480_592.953),
        ("2026-10-20T10:16:32Z", 1_792_491_392.0),
        ("2026-10-20 13:16:32+03:00", 1_792_491_392.0),
        ("2026-10-20T13:16:32+0300", 1_792_491_392.0),
    ])
    func timestamps(string: String, epoch: Double) throws {
        let date = try #require(KhalaDateParser.timestamp(string))
        #expect(abs(date.timeIntervalSince1970 - epoch) < 0.001)
    }

    @Test(arguments: ["unknown", "unavailable", "2026-10-20", "2026-10-20T10:16:32", "06:30:00", ""])
    func notTimestamps(string: String) {
        #expect(KhalaDateParser.timestamp(string) == nil)
    }

    @Test func timesOfDay() {
        #expect(KhalaDateParser.timeOfDay("22:00") == 79200)
        #expect(KhalaDateParser.timeOfDay("06:30:15") == 23415)
        #expect(KhalaDateParser.timeOfDay("24:00") == nil)
        #expect(KhalaDateParser.timeOfDay("sensor.next_alarm") == nil)
    }

    @Test func durations() {
        #expect(KhalaDateParser.duration("-00:30:00") == -1800)
        #expect(KhalaDateParser.duration("01:15") == 4500)
        #expect(KhalaDateParser.duration(90) == 90)
        #expect(KhalaDateParser.duration(["hours": 1, "minutes": 30]) == 5400)
        #expect(KhalaDateParser.duration("soon") == nil)
    }

    @Test func entityReadsTheAttributesItNeeds() {
        let sun = KhalaTestFixtures.entity("sun.sun", "above_horizon", ["next_setting": "2026-10-20T15:02:16.933537+00:00"])
        #expect(sun.domain == "sun")
        #expect(sun.nextSetting != nil)
        #expect(sun.name == "sun.sun")
        let heater = KhalaTestFixtures.entity("water_heater.tank", "eco", ["current_temperature": NSNumber(value: 51.6)])
        #expect(KhalaText.stateText(for: heater) == "52°")
    }

    @Test func stateTexts() {
        #expect(KhalaText.humanized(state: "not_home") == "Away")
        #expect(KhalaText.humanized(state: "heat_cool") == "Heat cool")
        #expect(KhalaText.humanized(state: "unknown") == "—")
        #expect(KhalaText.measurement(301.57, unit: "km") == "302 km")
        #expect(KhalaText.measurement(0.5, unit: "kW") == "0.5 kW")
        #expect(KhalaText.measurement(20.8, unit: "°C") == "21°")
        #expect(KhalaText.duration(5 * 3600 + 32 * 60) == "5 h 32 m")
        #expect(KhalaText.duration(45 * 60) == "45 m")
    }

    @Test func drawerDecisions() {
        #expect(KhalaDrawerMath.openWidth(container: 390) == 312)
        #expect(KhalaDrawerMath.openWidth(container: 1024) == 360)
        #expect(KhalaDrawerMath.progress(isOpen: false, travel: 156, openWidth: 312) == 0.5)
        #expect(KhalaDrawerMath.progress(isOpen: true, travel: 40, openWidth: 312) == 1)
        // A flick wins over distance; distance wins over staying put.
        #expect(KhalaDrawerMath.opensAfterRelease(wasOpen: false, travel: 20, projectedTravel: 200))
        #expect(!KhalaDrawerMath.opensAfterRelease(wasOpen: true, travel: 10, projectedTravel: -150))
        #expect(KhalaDrawerMath.opensAfterRelease(wasOpen: false, travel: 80, projectedTravel: 90))
        #expect(KhalaDrawerMath.opensAfterRelease(wasOpen: true, travel: -20, projectedTravel: -30))
    }
}
