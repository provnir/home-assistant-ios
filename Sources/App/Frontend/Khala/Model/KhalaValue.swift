import Foundation

/// Reads loosely typed JSON values out of Home Assistant attribute dictionaries. HAKit hands attributes over as
/// `[String: Any]` straight from `JSONSerialization`, so a number can arrive as `Double`, `Int` or `NSNumber`
/// and a list as `[Any]`; these helpers accept all of them the same way on every platform.
enum KhalaValue {
    static func double(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        guard let number = double(value) else { return nil }
        return Int(number)
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool: return value
        case let value as NSNumber: return value.boolValue
        case let value as String:
            switch value.lowercased() {
            case "true", "on", "yes": return true
            case "false", "off", "no": return false
            default: return nil
            }
        default: return nil
        }
    }

    static func string(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    /// A value Home Assistant allows as "one or a list of" (`at`, `weekday`, `trigger`, ...), always as a list.
    static func list(_ value: Any?) -> [Any] {
        switch value {
        case nil: return []
        case let array as [Any]: return array
        case let some?: return [some]
        }
    }

    /// Like `list`, keeping only the dictionaries.
    static func dictionaries(_ value: Any?) -> [[String: Any]] {
        list(value).compactMap { $0 as? [String: Any] }
    }
}
