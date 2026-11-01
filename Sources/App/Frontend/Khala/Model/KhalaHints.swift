import Foundation

/// The integration hints Khala ships (`Resources/khala-hints.json`, see `KhalaHint`). The file holds integration
/// knowledge only — which `translation_key` of which platform is a car's battery, a boiler's timer — and no home
/// data. Layouts take a `KhalaHints` value so tests can hand in their own; the app uses `builtIn`.
struct KhalaHints: Equatable {
    let entries: [KhalaHint]

    /// No hints: everything falls back to domain and device class.
    static let empty = KhalaHints(entries: [])

    /// The file in the app bundle (in the Linux check, the staged package's resources). Empty when it is missing
    /// or unreadable; `KhalaHomeViewModel` logs that, and `archive.sh` refuses an archive without the file.
    static let builtIn: KhalaHints = load(from: resourceBundle) ?? .empty

    static let resourceName = "khala-hints"

    /// The hint for `entity`, from its registry platform, domain and translation key; nil without a platform.
    func hint(for entity: KhalaEntity) -> KhalaHint? {
        guard let platform = entity.platform else { return nil }
        return hint(platform: platform, domain: entity.domain, translationKey: entity.translationKey)
    }

    /// The most specific matching entry; ties go to the one listed first.
    func hint(platform: String, domain: String, translationKey: String?) -> KhalaHint? {
        var best: KhalaHint?
        for entry in entries where entry.matches(platform: platform, domain: domain, translationKey: translationKey) {
            if best == nil || entry.specificity > best!.specificity { best = entry }
        }
        return best
    }

    // MARK: - Loading

    private struct File: Decodable {
        let version: Int
        let hints: [KhalaHint]
    }

    static func decode(_ data: Data) throws -> KhalaHints {
        KhalaHints(entries: try JSONDecoder().decode(File.self, from: data).hints)
    }

    static func load(from bundle: Bundle) -> KhalaHints? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    #if SWIFT_PACKAGE
    private static var resourceBundle: Bundle { .module }
    #else
    private static var resourceBundle: Bundle { .main }
    #endif
}
