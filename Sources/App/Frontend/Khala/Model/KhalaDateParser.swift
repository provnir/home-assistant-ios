import Foundation

/// Parses the date and time strings Home Assistant puts in states and attributes, identically on every platform
/// (`ISO8601DateFormatter` disagrees across OS versions on six-digit fractions, which HA uses for `next_rising`).
///
/// Handles `2026-10-21T03:48:30.681916+00:00`, `2026-10-20T07:16:32.953+00:00`, `...Z`, a space instead of `T`,
/// time-of-day strings (`22:00`, `22:00:15`) and HA's `time_period` offsets (`-00:30:00`, seconds, or a
/// `{hours:, minutes:, seconds:}` dictionary).
enum KhalaDateParser {
    /// An absolute timestamp with an explicit zone. Strings without a zone are rejected: their meaning depends on
    /// the server's time zone, which the app does not know here.
    static func timestamp(_ string: String) -> Date? {
        let bytes = Array(string.utf8)
        guard bytes.count >= 19,
              let year = number(bytes, 0, 4), bytes[4] == UInt8(ascii: "-"),
              let month = number(bytes, 5, 2), bytes[7] == UInt8(ascii: "-"),
              let day = number(bytes, 8, 2),
              bytes[10] == UInt8(ascii: "T") || bytes[10] == UInt8(ascii: " "),
              let hour = number(bytes, 11, 2), bytes[13] == UInt8(ascii: ":"),
              let minute = number(bytes, 14, 2), bytes[16] == UInt8(ascii: ":"),
              let second = number(bytes, 17, 2),
              (1 ... 12).contains(month), (1 ... 31).contains(day), hour < 24, minute < 60, second < 61 else {
            return nil
        }

        var index = 19
        var fraction = 0.0
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            var scale = 0.1
            while index < bytes.count, let digit = digit(bytes[index]) {
                fraction += Double(digit) * scale
                scale /= 10
                index += 1
            }
        }

        guard index < bytes.count else { return nil }
        let offsetSeconds: Int
        switch bytes[index] {
        case UInt8(ascii: "Z"), UInt8(ascii: "z"):
            offsetSeconds = 0
        case UInt8(ascii: "+"), UInt8(ascii: "-"):
            let sign = bytes[index] == UInt8(ascii: "-") ? -1 : 1
            guard let offsetHours = number(bytes, index + 1, 2) else { return nil }
            var offsetMinutes = 0
            if index + 3 < bytes.count {
                let minuteStart = bytes[index + 3] == UInt8(ascii: ":") ? index + 4 : index + 3
                offsetMinutes = number(bytes, minuteStart, 2) ?? 0
            }
            offsetSeconds = sign * (offsetHours * 3600 + offsetMinutes * 60)
        default:
            return nil
        }

        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86400 + hour * 3600 + minute * 60 + second - offsetSeconds
        return Date(timeIntervalSince1970: TimeInterval(seconds) + fraction)
    }

    /// Seconds after local midnight for `HH:MM` or `HH:MM:SS`; nil for anything else (entity ids, templates).
    static func timeOfDay(_ string: String) -> Int? {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 2 && $0.allSatisfy(\.isNumber) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              hour < 24, minute < 60 else {
            return nil
        }
        let second = parts.count == 3 ? Int(parts[2]) ?? 0 : 0
        guard second < 60 else { return nil }
        return hour * 3600 + minute * 60 + second
    }

    /// A Home Assistant `time_period`: `"-00:30:00"`, `"01:15"`, a number of seconds, or a dictionary of
    /// `days`/`hours`/`minutes`/`seconds`/`milliseconds`. Nil when it can't be read.
    static func duration(_ value: Any?) -> TimeInterval? {
        guard let value else { return nil }
        if let number = KhalaValue.double(value) {
            return number
        }
        if let string = value as? String {
            var text = string.trimmingCharacters(in: .whitespaces)
            var sign = 1.0
            if text.hasPrefix("-") {
                sign = -1
                text.removeFirst()
            } else if text.hasPrefix("+") {
                text.removeFirst()
            }
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2 || parts.count == 3 else { return nil }
            let numbers = parts.map { Double($0) }
            guard numbers.allSatisfy({ $0 != nil }) else { return nil }
            let values = numbers.compactMap { $0 }
            let total = values[0] * 3600 + values[1] * 60 + (values.count == 3 ? values[2] : 0)
            return sign * total
        }
        if let dictionary = value as? [String: Any] {
            let days = KhalaValue.double(dictionary["days"]) ?? 0
            let hours = KhalaValue.double(dictionary["hours"]) ?? 0
            let minutes = KhalaValue.double(dictionary["minutes"]) ?? 0
            let seconds = KhalaValue.double(dictionary["seconds"]) ?? 0
            let milliseconds = KhalaValue.double(dictionary["milliseconds"]) ?? 0
            return days * 86400 + hours * 3600 + minutes * 60 + seconds + milliseconds / 1000
        }
        return nil
    }

    // MARK: - Private

    private static func digit(_ byte: UInt8) -> Int? {
        guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
        return Int(byte - UInt8(ascii: "0"))
    }

    private static func number(_ bytes: [UInt8], _ start: Int, _ length: Int) -> Int? {
        guard start >= 0, start + length <= bytes.count else { return nil }
        var value = 0
        for index in start ..< start + length {
            guard let digit = digit(bytes[index]) else { return nil }
            value = value * 10 + digit
        }
        return value
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date (H. Hinnant's `days_from_civil`).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let shiftedMonth = (month + 9) % 12
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
