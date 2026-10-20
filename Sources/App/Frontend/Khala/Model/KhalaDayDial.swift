import Foundation

/// Geometry of the 24-hour dial on the hot-water hero (mockup `DayWater`): midnight at the bottom, 06 on the left,
/// noon at the top, 18 on the right — the day runs clockwise and the sun band sits over the top. Angles are degrees
/// clockwise from 12 o'clock, so SwiftUI/Canvas code can turn them into points with `point(angle:radius:)`.
struct KhalaDayDial: Equatable {
    /// A band on the ring, start→end clockwise, in seconds after midnight.
    struct Band: Equatable {
        let start: Int
        let end: Int
    }

    /// Sunrise→sunset today, when the `sun` entity says.
    var sun: Band?
    /// The windows automations run the device in (start + run length; a zero-length window is a mark).
    var windows: [Band]
    /// Now, in seconds after midnight.
    var now: Int

    static let secondsPerDay = 86400

    /// Degrees clockwise from the top for a time of day.
    static func angle(secondsOfDay: Int) -> Double {
        let fraction = Double(((secondsOfDay % secondsPerDay) + secondsPerDay) % secondsPerDay) / Double(secondsPerDay)
        return (180 + fraction * 360).truncatingRemainder(dividingBy: 360)
    }

    /// A point on a circle of `radius` around the origin for an angle from `angle(secondsOfDay:)`, in screen
    /// coordinates (y grows downwards).
    static func point(angle: Double, radius: Double) -> (x: Double, y: Double) {
        let radians = angle * .pi / 180
        return (radius * sin(radians), -radius * cos(radians))
    }

    /// The clockwise sweep of a band in degrees (a band past midnight wraps).
    static func sweep(_ band: Band) -> Double {
        let length = ((band.end - band.start) % secondsPerDay + secondsPerDay) % secondsPerDay
        return Double(length) / Double(secondsPerDay) * 360
    }

    static func secondsOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
    }

    /// The dial for now: today's sun band from the `sun` entity (today's rise/set ≈ next minus a day once passed)
    /// and one window per literal trigger time of the device's targeting automations.
    static func build(
        sun: KhalaEntity?,
        automations: [KhalaDeviceAutomation],
        now: Date,
        calendar: Calendar
    ) -> KhalaDayDial {
        var band: Band?
        if let rising = sun?.nextRising, let setting = sun?.nextSetting {
            band = Band(
                start: secondsOfDay(rising, calendar: calendar),
                end: secondsOfDay(setting, calendar: calendar)
            )
        }
        var windows: [Band] = []
        for automation in automations where automation.targetsDevice {
            for start in automation.timesOfDay {
                windows.append(Band(start: start, end: start + (automation.runMinutes ?? 0) * 60))
            }
        }
        return KhalaDayDial(sun: band, windows: windows, now: secondsOfDay(now, calendar: calendar))
    }

    /// "07:30–08:15", for the dial's accessibility label and the window caption.
    static func text(_ band: Band) -> String {
        func clock(_ seconds: Int) -> String {
            let value = ((seconds % secondsPerDay) + secondsPerDay) % secondsPerDay
            return String(format: "%02d:%02d", value / 3600, (value % 3600) / 60)
        }
        return band.end == band.start ? clock(band.start) : "\(clock(band.start))–\(clock(band.end))"
    }
}
