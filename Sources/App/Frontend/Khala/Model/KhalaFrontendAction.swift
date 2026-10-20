import Foundation

/// One of the dashboard's own actions (search, Assist, add device/automation/area/person, edit dashboard,
/// refresh, …) read off the frontend's hidden toolbar, so the native header's "More" menu offers exactly what
/// the frontend would and performs it through the frontend's own handler. `key` is the frontend's translation
/// key when it has one (`ui.panel.lovelace.menu.search_home_assistant`), which picks the native glyph. An action
/// with `children` is a group (the frontend's "Add" dropdown).
struct KhalaFrontendAction: Hashable, Identifiable {
    let id: String
    let title: String
    let key: String?
    let children: [KhalaFrontendAction]

    init(id: String, title: String, key: String? = nil, children: [KhalaFrontendAction] = []) {
        self.id = id
        self.title = title
        self.key = key
        self.children = children
    }

    init?(json: Any?) {
        guard let json = json as? [String: Any], let id = KhalaValue.string(json["id"]),
              let title = KhalaValue.string(json["title"]) else {
            return nil
        }
        self.init(
            id: id,
            title: title,
            key: KhalaValue.string(json["key"]),
            children: (json["children"] as? [Any] ?? []).compactMap(KhalaFrontendAction.init(json:))
        )
    }

    /// What the native menu draws for the frontend's known actions; nil leaves the row text-only.
    enum Glyph: Equatable {
        case search, assist, add, edit, refresh, list, device, automation, area, person
    }

    var glyph: Glyph? {
        guard let key else { return nil }
        let table: [(String, Glyph)] = [
            ("search", .search), ("assist", .assist), ("add_device", .device), ("create_automation", .automation),
            ("create_area", .area), ("add_person", .person), ("menu.add", .add), ("configure_ui", .edit),
            ("refresh", .refresh), ("reload", .refresh), ("unused_entities", .list), ("edit", .edit),
        ]
        return table.first { key.contains($0.0) }?.1
    }
}
