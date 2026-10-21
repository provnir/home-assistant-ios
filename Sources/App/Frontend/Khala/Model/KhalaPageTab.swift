import Foundation

/// One tab of a tabbed Home Assistant page (`hass-tabs-subpage.tabs`, the ones the frontend shows), lifted into
/// Khala's bottom glass sub-tabs. Selecting one navigates the way the frontend's own tab does.
struct KhalaPageTab: Hashable, Identifiable {
    let path: String
    let title: String
    let isActive: Bool

    var id: String { path }

    init(path: String, title: String, isActive: Bool) {
        self.path = path
        self.title = title
        self.isActive = isActive
    }

    init?(json: Any?) {
        guard let json = json as? [String: Any], let path = KhalaValue.string(json["path"]),
              let title = KhalaValue.string(json["title"]) else {
            return nil
        }
        self.init(path: path, title: title, isActive: KhalaValue.bool(json["active"]) ?? false)
    }

    /// The glyph Khala draws for a tab, by the page it opens.
    var glyph: KhalaSettingsGlyph {
        let path = KhalaSettingsCatalog.normalized(path)
        for section in KhalaSettingsCatalog.sections {
            if let page = section.pages.first(where: { $0.path == path }) { return page.glyph }
        }
        return .page
    }
}
