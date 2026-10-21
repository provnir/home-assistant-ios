import Foundation

/// The Settings screen's search over app and server settings: a static index (`KhalaSettingsEntry`), matched
/// case- and diacritic-insensitively, best matches first — a title that starts with the query, then one with a
/// word that does, then one containing it, then a match on a keyword — each target once.
enum KhalaSettingsSearch {
    static func results(for query: String, in entries: [KhalaSettingsEntry]) -> [KhalaSettingsEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var best: [KhalaSettingsEntry.Target: (rank: Int, order: Int, entry: KhalaSettingsEntry)] = [:]
        for (order, entry) in entries.enumerated() {
            guard let rank = rank(of: entry, query: query) else { continue }
            if let existing = best[entry.target], existing.rank <= rank { continue }
            best[entry.target] = (rank, order, entry)
        }
        return best.values
            .sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }
            .map(\.entry)
    }

    /// 0 = title starts with the query, 1 = a word of the title does, 2 = the title contains it, 3 = a keyword
    /// contains it, 4 = where it lives does; nil = no match.
    static func rank(of entry: KhalaSettingsEntry, query: String) -> Int? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if let range = entry.title.range(of: query, options: options) {
            if range.lowerBound == entry.title.startIndex { return 0 }
            let before = entry.title[entry.title.index(before: range.lowerBound)]
            return before.isLetter || before.isNumber ? 2 : 1
        }
        if entry.keywords.contains(where: { $0.range(of: query, options: options) != nil }) { return 3 }
        if let subtitle = entry.subtitle, subtitle.range(of: query, options: options) != nil { return 4 }
        return nil
    }
}
