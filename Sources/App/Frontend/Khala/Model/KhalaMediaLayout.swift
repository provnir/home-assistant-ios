import Foundation

/// The media sheet (mockup `DayTheater`) for a `media_player`: power, a volume slider, a source grid and a sound-mode
/// dropdown, each only when the player supports it (`MediaPlayerEntityFeature`: VOLUME_SET 4, TURN_ON 128,
/// TURN_OFF 256, SELECT_SOURCE 2048, SELECT_SOUND_MODE 65536) and has something to offer.
struct KhalaMediaLayout: Equatable {
    let entityId: String
    let name: String
    let isOn: Bool
    let isUnavailable: Bool
    /// "On · HEOS Music", "Off", "Playing · Spotify".
    let stateLine: String
    let canPower: Bool
    /// 0...1, nil when the player can't set it or doesn't report it.
    let volume: Double?
    let isMuted: Bool
    let sources: [String]
    let source: String?
    let soundModes: [String]
    let soundMode: String?
    let isReceiver: Bool

    init(entity: KhalaEntity, attributes: [String: Any], name: String? = nil) {
        let features = KhalaValue.int(attributes["supported_features"]) ?? 0
        func supports(_ flag: Int) -> Bool { features & flag != 0 }
        entityId = entity.entityId
        self.name = name ?? entity.name
        isUnavailable = entity.isUnavailable
        isOn = !["off", "standby", "unavailable", "unknown"].contains(entity.state)
        canPower = supports(128) || supports(256)
        let level = KhalaValue.double(attributes["volume_level"])
        volume = supports(4) ? (level ?? (isOn ? 0 : nil)) : nil
        isMuted = KhalaValue.bool(attributes["is_volume_muted"]) ?? false
        let sourceList = KhalaValue.list(attributes["source_list"]).compactMap { $0 as? String }
        sources = supports(2048) ? sourceList : []
        source = KhalaValue.string(attributes["source"])
        let modeList = KhalaValue.list(attributes["sound_mode_list"]).compactMap { $0 as? String }
        soundModes = supports(65536) ? modeList : []
        soundMode = KhalaValue.string(attributes["sound_mode"])
        isReceiver = entity.deviceClass == "receiver" || !modeList.isEmpty
        let stateWord = isOn && entity.state == "on" ? KhalaScreenText.on : KhalaText.humanized(state: entity.state)
        if isOn, let source, !source.isEmpty {
            stateLine = "\(stateWord) · \(source)"
        } else {
            stateLine = stateWord
        }
    }

    func power(on: Bool) -> KhalaServiceCall {
        KhalaServiceCall("media_player", on ? "turn_on" : "turn_off", entityId: entityId)
    }

    func setVolume(_ level: Double) -> KhalaServiceCall {
        let clamped = (min(1, max(0, level)) * 100).rounded() / 100
        return KhalaServiceCall("media_player", "volume_set", entityId: entityId, data: ["volume_level": clamped])
    }

    func selectSource(_ name: String) -> KhalaServiceCall {
        KhalaServiceCall("media_player", "select_source", entityId: entityId, data: ["source": name])
    }

    func selectSoundMode(_ name: String) -> KhalaServiceCall {
        KhalaServiceCall("media_player", "select_sound_mode", entityId: entityId, data: ["sound_mode": name])
    }

    /// "45%" for the volume header.
    static func volumeText(_ level: Double) -> String {
        "\(Int((level * 100).rounded()))%"
    }
}
