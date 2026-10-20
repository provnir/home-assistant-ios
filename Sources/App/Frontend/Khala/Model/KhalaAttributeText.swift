import Foundation

/// Turns an entity's raw attributes into readable rows for the Settings and generic screens. Credentials and
/// bookkeeping never show: `access_token` (a camera's signed-URL token), `entity_picture` (which embeds it),
/// `friendly_name`, `icon`, `supported_features`.
enum KhalaAttributeText {
    static let hidden: Set<String> = [
        "access_token", "entity_picture", "friendly_name", "icon", "supported_features", "attribution",
    ]

    static func rows(_ attributes: [String: Any]) -> [KhalaAttributeRow] {
        attributes.keys
            .filter { !hidden.contains($0) }
            .sorted()
            .compactMap { key in
                guard let text = text(attributes[key]), !text.isEmpty else { return nil }
                return KhalaAttributeRow(key: label(key), value: text)
            }
    }

    /// `color_temp_kelvin` → "Color temp kelvin".
    static func label(_ key: String) -> String {
        let spaced = key.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    static func text(_ value: Any?) -> String? {
        switch value {
        case nil, is NSNull: return nil
        case let string as String: return string
        case let bool as Bool: return bool ? "Yes" : "No"
        case let number as Int: return String(number)
        case let number as Double: return KhalaText.measurement(number, unit: nil)
        case let array as [Any]:
            let parts = array.compactMap { text($0) }
            return parts.count > 12 ? parts.prefix(12).joined(separator: ", ") + " …" : parts.joined(separator: ", ")
        case is [String: Any]: return nil
        case let some?: return String(describing: some)
        }
    }
}
