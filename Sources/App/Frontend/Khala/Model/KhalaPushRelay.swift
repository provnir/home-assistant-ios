import Foundation

/// Khala's own push relay (a Cloudflare Worker, `Configuration/Khala/push-relay`): when the build carries its URL, the
/// app registers that URL and its raw APNs device token with Home Assistant instead of Firebase's, because Home
/// Assistant's relay only delivers to the official app's bundle id. Without the key the app behaves as upstream.
enum KhalaPushRelay {
    static let infoKey = "KhalaPushRelayURL"

    static var url: URL? { url(info: Bundle.main.infoDictionary ?? [:]) }
    static var isEnabled: Bool { url != nil }

    static func url(info: [String: Any]) -> URL? {
        guard let text = info[infoKey] as? String, let url = URL(string: text),
              url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}
