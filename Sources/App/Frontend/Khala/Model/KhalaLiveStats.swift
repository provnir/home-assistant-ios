import Foundation

/// The live player's info sheet (long press): what the page reads from `RTCPeerConnection.getStats()` (WebRTC) or
/// the video element's WebKit counters (HLS), turned into rows. The page sends raw counters; rates come from two
/// samples here, so the parsing is testable and the page stays small.
struct KhalaLiveStats: Equatable {
    /// One reading, as `window.khala.stats()` returns it.
    struct Sample: Equatable {
        enum Lane: String {
            case webRTC = "webrtc"
            case hls
        }

        let lane: Lane
        /// Milliseconds (`RTCStats.timestamp`, or `performance.now()` for HLS).
        let timestamp: Double
        let bytes: Double?
        let framesDecoded: Double?
        let framesPerSecond: Double?
        let width: Int?
        let height: Int?
        let framesDropped: Double?
        let packetsLost: Double?
        /// Seconds.
        let jitter: Double?
        /// "video/H265".
        let codec: String?
        /// Seconds (`candidate-pair.currentRoundTripTime`).
        let roundTripTime: Double?
        /// `host`, `srflx`, `prflx`, `relay`.
        let localCandidate: String?
        let remoteCandidate: String?
        let transport: String?
        /// HLS only: seconds behind the live edge.
        let behindLive: Double?

        init?(json: [String: Any]) {
            guard let lane = (json["lane"] as? String).flatMap(Lane.init(rawValue:)),
                  let timestamp = Self.number(json["t"]) else { return nil }
            self.lane = lane
            self.timestamp = timestamp
            bytes = Self.number(json["bytes"])
            framesDecoded = Self.number(json["frames"])
            framesPerSecond = Self.number(json["fps"])
            width = Self.number(json["w"]).flatMap { KhalaJSON.int($0) }
            height = Self.number(json["h"]).flatMap { KhalaJSON.int($0) }
            framesDropped = Self.number(json["dropped"])
            packetsLost = Self.number(json["lost"])
            jitter = Self.number(json["jitter"])
            codec = json["codec"] as? String
            roundTripTime = Self.number(json["rtt"])
            localCandidate = json["local"] as? String
            remoteCandidate = json["remote"] as? String
            transport = json["protocol"] as? String
            behindLive = Self.number(json["behind"])
        }

        /// A finite number, whatever JSON type it came as.
        private static func number(_ value: Any?) -> Double? {
            let double: Double?
            if let value = value as? Double {
                double = value
            } else if let value = value as? Int {
                double = Double(value)
            } else if let value = value as? NSNumber {
                double = value.doubleValue
            } else {
                double = nil
            }
            guard let double, double.isFinite else { return nil }
            return double
        }
    }

    let transport: String
    let codec: String?
    let resolution: String?
    let framesPerSecond: Double?
    /// Kilobits per second over the two samples.
    let bitrate: Double?
    /// Milliseconds.
    let roundTripTime: Double?
    let route: String?
    let packetsLost: Int?
    let framesDropped: Int?
    /// Milliseconds.
    let jitter: Double?
    let behindLive: Double?

    /// - Parameters:
    ///   - codec: the codec when the sample has none (HLS: from the playlist).
    init(_ sample: Sample, previous: Sample?, codec fallbackCodec: String? = nil) {
        transport = sample.lane == .webRTC ? "WebRTC" : "HLS"
        codec = sample.codec.map(KhalaWebRTCSignaling.codecName(mimeType:)) ?? fallbackCodec
        if let width = sample.width, let height = sample.height, width > 0, height > 0 {
            resolution = "\(width)×\(height)"
        } else {
            resolution = nil
        }
        let previous = previous.flatMap { $0.lane == sample.lane && sample.timestamp > $0.timestamp ? $0 : nil }
        let seconds = previous.map { (sample.timestamp - $0.timestamp) / 1000 }
        if let fps = sample.framesPerSecond, fps > 0 {
            framesPerSecond = fps
        } else if let seconds, let now = sample.framesDecoded, let then = previous?.framesDecoded, now >= then {
            framesPerSecond = (now - then) / seconds
        } else {
            framesPerSecond = nil
        }
        if let seconds, let now = sample.bytes, let then = previous?.bytes, now >= then {
            bitrate = (now - then) * 8 / 1000 / seconds
        } else {
            bitrate = nil
        }
        roundTripTime = sample.roundTripTime.map { $0 * 1000 }
        route = Self.route(local: sample.localCandidate, remote: sample.remoteCandidate, transport: sample.transport)
        packetsLost = sample.packetsLost.flatMap { KhalaJSON.int($0) }
        framesDropped = sample.framesDropped.flatMap { KhalaJSON.int($0) }
        jitter = sample.jitter.map { $0 * 1000 }
        behindLive = sample.behindLive
    }

    /// "Direct · UDP", "Relay (TURN) · UDP", "Via STUN · TCP".
    static func route(local: String?, remote: String?, transport: String?) -> String? {
        guard local != nil || remote != nil else { return nil }
        let kind: String
        if local == "relay" || remote == "relay" {
            kind = "Relay (TURN)"
        } else if local == "host", remote == "host" {
            kind = "Direct"
        } else {
            kind = "Via STUN"
        }
        return ([kind] + (transport.map { [$0.uppercased()] } ?? [])).joined(separator: " · ")
    }

    struct Row: Hashable {
        let title: String
        let value: String

        init(_ title: String, _ value: String) {
            self.title = title
            self.value = value
        }
    }

    /// The sheet's rows, in order; values not known are left out.
    var rows: [Row] {
        var rows = [Row("Path", transport)]
        if let codec { rows.append(Row("Codec", codec)) }
        if let resolution { rows.append(Row("Resolution", resolution)) }
        if let framesPerSecond { rows.append(Row("Frame rate", String(format: "%.0f fps", framesPerSecond))) }
        if let bitrate { rows.append(Row("Bitrate", Self.bitrateText(bitrate))) }
        if let roundTripTime { rows.append(Row("Round trip", String(format: "%.0f ms", roundTripTime))) }
        if let route { rows.append(Row("Route", route)) }
        if let jitter { rows.append(Row("Jitter", String(format: "%.0f ms", jitter))) }
        if let packetsLost { rows.append(Row("Packets lost", "\(packetsLost)")) }
        if let framesDropped { rows.append(Row("Frames dropped", "\(framesDropped)")) }
        if let behindLive { rows.append(Row("Behind live", String(format: "%.1f s", behindLive))) }
        return rows
    }

    /// "850 kbps", "5.8 Mbps".
    static func bitrateText(_ kilobits: Double) -> String {
        kilobits >= 1000 ? String(format: "%.1f Mbps", kilobits / 1000) : String(format: "%.0f kbps", kilobits)
    }
}
