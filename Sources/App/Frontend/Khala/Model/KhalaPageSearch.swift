import Foundation

/// A Home Assistant page's own search field (the data tables' and the integrations page's `ha-input-search`),
/// lifted into Khala's glass search field, which types into it.
struct KhalaPageSearch: Hashable {
    let placeholder: String?
    let value: String

    init(placeholder: String?, value: String = "") {
        self.placeholder = placeholder
        self.value = value
    }

    init?(json: Any?) {
        guard let json = json as? [String: Any] else { return nil }
        self.init(placeholder: KhalaValue.string(json["placeholder"]), value: KhalaValue.string(json["value"]) ?? "")
    }
}
