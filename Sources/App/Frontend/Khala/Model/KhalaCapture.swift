import Foundation

/// A still a camera saved when it detected something: a file Home Assistant serves through a media source.
///
/// Many homes run an automation that saves a snapshot on every detection (`camera.snapshot` into a folder listed
/// under `media_dirs`). Khala shows that capture on the detection's card and in its full-screen viewer, instead of
/// the live stream. Which folder and how files are named is data (`KhalaCaptureConfig`); the common layout is the
/// default and is found on its own.
struct KhalaCapture: Equatable, Identifiable, Hashable {
    /// The file's `media-source://` id, resolved to a signed URL when it is shown.
    let mediaContentId: String
    /// The camera entity's object id the file names (`front_door` for `camera.front_door`).
    let cameraObjectId: String
    /// When the capture was taken, read from its folder and file name in the server's time zone.
    let date: Date

    var id: String { mediaContentId }
}

/// Where a home's detection captures live and how they are named.
struct KhalaCaptureConfig: Equatable {
    /// The media-source folder holding one folder per day (`media-source://media_source/<dir>`); nil = find it
    /// (`KhalaCaptureIndex.looksLikeCaptureRoot`).
    var rootId: String?
    /// A day folder's name (`2026-10-21`), as a `DateFormatter` format.
    var dayFolderFormat: String
    /// A capture's file name: group 1 is the time of day (`HHmmss`), group 2 the camera's object id.
    var filePattern: String
    /// A detection and a capture belong together when they are at most this far apart.
    var matchWindow: TimeInterval

    /// `<YYYY-MM-DD>/<HHMMSS>_<camera_object_id>.jpg`, matched within ±90 s.
    static let standard = KhalaCaptureConfig(
        rootId: nil,
        dayFolderFormat: "yyyy-MM-dd",
        filePattern: #"^([0-9]{6})_([a-z0-9_]+)\.(?:jpe?g|png)$"#,
        matchWindow: 90
    )
}

/// One entry of a `media_source/browse_media` answer (HA core `components/media_source`, `BrowseMedia.as_dict`).
struct KhalaMediaNode: Equatable {
    let title: String
    let mediaContentId: String
    let canExpand: Bool

    init(title: String, mediaContentId: String, canExpand: Bool) {
        self.title = title
        self.mediaContentId = mediaContentId
        self.canExpand = canExpand
    }

    init?(json: Any?) {
        guard let json = json as? [String: Any], let id = KhalaValue.string(json["media_content_id"]) else {
            return nil
        }
        self.init(
            title: KhalaValue.string(json["title"]) ?? "",
            mediaContentId: id,
            canExpand: KhalaValue.bool(json["can_expand"]) ?? false
        )
    }

    /// The children of a browse answer.
    static func children(of response: [String: Any]) -> [KhalaMediaNode] {
        (response["children"] as? [Any] ?? []).compactMap(KhalaMediaNode.init(json:))
    }
}

/// The pure rules of finding, reading and matching captures; `KhalaMediaSourceCaptures` does the browsing.
enum KhalaCaptureIndex {
    /// Where media-source folders start (`media_dirs`; with a single one, its contents are listed right here).
    static let mediaSourceRoot = "media-source://media_source"

    /// The folder holding a media id (`…/caps` for `…/caps/2026-10-21`).
    static func parentId(of mediaContentId: String) -> String {
        guard let slash = mediaContentId.range(of: "/", options: .backwards),
              !mediaContentId[..<slash.lowerBound].hasSuffix("/") else { return mediaContentId }
        return String(mediaContentId[..<slash.lowerBound])
    }

    /// The last part of a media id (`2026-10-21` for `…/caps/2026-10-21`).
    static func lastComponent(of mediaContentId: String) -> String {
        mediaContentId.split(separator: "/").last.map(String.init) ?? mediaContentId
    }

    /// The captures folder whose contents `children` are: the parent of their day folders, if they are some.
    static func root(of children: [KhalaMediaNode], config: KhalaCaptureConfig, timeZone: TimeZone) -> String? {
        guard let day = children.first(where: {
            $0.canExpand && self.day(ofFolder: $0.title, config: config, timeZone: timeZone) != nil
        }) else { return nil }
        return parentId(of: day.mediaContentId)
    }

    /// `front_door` for `camera.front_door`.
    static func objectId(of entityId: String) -> String {
        entityId.split(separator: ".", maxSplits: 1).last.map(String.init) ?? entityId
    }

    /// The day folder's name for `date` in the server's time zone.
    static func dayFolder(for date: Date, config: KhalaCaptureConfig, timeZone: TimeZone) -> String {
        formatter(config.dayFolderFormat, timeZone: timeZone).string(from: date)
    }

    /// The start of the day a day folder stands for, nil when the name isn't one.
    static func day(ofFolder name: String, config: KhalaCaptureConfig, timeZone: TimeZone) -> Date? {
        let formatter = formatter(config.dayFolderFormat, timeZone: timeZone)
        guard let date = formatter.date(from: name), formatter.string(from: date) == name else { return nil }
        return date
    }

    /// A folder whose sub-folders are day folders holds captures (the auto-detection rule).
    static func looksLikeCaptureRoot(_ children: [KhalaMediaNode], config: KhalaCaptureConfig, timeZone: TimeZone) -> Bool {
        children.contains { $0.canExpand && day(ofFolder: $0.title, config: config, timeZone: timeZone) != nil }
    }

    /// The media id of the day folder for `date` under `rootId`.
    static func dayFolderId(rootId: String, date: Date, config: KhalaCaptureConfig, timeZone: TimeZone) -> String {
        rootId + "/" + dayFolder(for: date, config: config, timeZone: timeZone)
    }

    /// The captures among a day folder's files, oldest first; names that don't fit the pattern are skipped.
    static func captures(
        in files: [KhalaMediaNode],
        day: Date,
        config: KhalaCaptureConfig,
        timeZone: TimeZone
    ) -> [KhalaCapture] {
        guard let regex = try? NSRegularExpression(pattern: config.filePattern, options: [.caseInsensitive]) else {
            return []
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return files.compactMap { file -> KhalaCapture? in
            guard !file.canExpand else { return nil }
            let name = file.title as NSString
            guard let match = regex.firstMatch(in: file.title, range: NSRange(location: 0, length: name.length)),
                  match.numberOfRanges >= 3 else { return nil }
            let time = name.substring(with: match.range(at: 1))
            let camera = name.substring(with: match.range(at: 2)).lowercased()
            guard time.count == 6, let hour = Int(time.prefix(2)), let minute = Int(time.dropFirst(2).prefix(2)),
                  let second = Int(time.suffix(2)), hour < 24, minute < 60, second < 60 else { return nil }
            var parts = calendar.dateComponents([.year, .month, .day], from: day)
            parts.hour = hour
            parts.minute = minute
            parts.second = second
            guard let date = calendar.date(from: parts) else { return nil }
            return KhalaCapture(mediaContentId: file.mediaContentId, cameraObjectId: camera, date: date)
        }
        .sorted { $0.date < $1.date }
    }

    /// The capture of `cameraEntityId` nearest to a detection at `date`, if one is within the match window.
    static func match(
        cameraEntityId: String,
        date: Date,
        in captures: [KhalaCapture],
        config: KhalaCaptureConfig
    ) -> KhalaCapture? {
        let camera = objectId(of: cameraEntityId).lowercased()
        return captures
            .filter { $0.cameraObjectId == camera && abs($0.date.timeIntervalSince(date)) <= config.matchWindow }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
