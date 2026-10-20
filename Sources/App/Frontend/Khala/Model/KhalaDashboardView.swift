import Foundation

/// A selectable view of the dashboard on screen, as the frontend itself resolved it (strategy-generated views
/// included): its position in the dashboard's `views`, its `path` when it has one, title and icon. Sub-views and
/// views hidden from the user are never listed (the frontend's own tab bar hides them the same way).
struct KhalaDashboardView: Hashable, Identifiable {
    let index: Int
    let path: String?
    let title: String?
    let icon: String?

    var id: Int { index }

    init(index: Int, path: String?, title: String?, icon: String?) {
        self.index = index
        self.path = path
        self.title = title
        self.icon = icon
    }

    init?(json: Any?) {
        guard let json = json as? [String: Any], let index = KhalaValue.int(json["index"]), index >= 0 else {
            return nil
        }
        self.init(
            index: index,
            path: KhalaValue.string(json["path"]),
            title: KhalaValue.string(json["title"]),
            icon: KhalaValue.string(json["icon"])
        )
    }
}
