import Foundation

/// What a slider control sets.
enum KhalaSlider: Hashable {
    /// `light.turn_on` `brightness_pct`.
    case brightness
    /// `light.turn_on` `color_temp_kelvin`, within the light's own range (`LightCapabilities`).
    case colorTemp(minKelvin: Double, maxKelvin: Double)
    /// `cover.set_cover_position`.
    case position
    /// `cover.set_cover_tilt_position`.
    case tilt
    /// `media_player.volume_set`.
    case volume
    /// `fan.set_percentage`, snapping to the fan's `percentage_step`.
    case percentage(step: Double)

    /// The values the slider spans: 0...1 for volume (as HA reports it), kelvin for warmth, else 0...100.
    var range: ClosedRange<Double> {
        switch self {
        case .volume: return 0 ... 1
        case let .colorTemp(minKelvin, maxKelvin):
            let lower = min(minKelvin, maxKelvin)
            return lower ... max(minKelvin, maxKelvin, lower + 1)
        case .brightness, .position, .tilt, .percentage: return 0 ... 100
        }
    }

    /// `value` kept in `range` and on the slider's grid: a fan's speed on its `percentage_step` (a four-speed fan
    /// only stops at 0, 25, 50, 75, 100), kelvin on 50 K, the rest on whole percent.
    func snapped(_ value: Double) -> Double {
        let bounded = min(range.upperBound, max(range.lowerBound, value))
        switch self {
        case .volume: return (bounded * 100).rounded() / 100
        case .colorTemp: return min(range.upperBound, max(range.lowerBound, (bounded / 50).rounded() * 50))
        case let .percentage(step):
            guard step > 0 else { return bounded.rounded() }
            return min(range.upperBound, ((bounded / step).rounded() * step).rounded())
        case .brightness, .position, .tilt: return bounded.rounded()
        }
    }

    /// Where `value` sits in `range`, 0...1.
    func fraction(_ value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    /// The value at `fraction` (0...1) of `range`, snapped.
    func value(atFraction fraction: Double) -> Double {
        snapped(range.lowerBound + min(1, max(0, fraction)) * (range.upperBound - range.lowerBound))
    }

    /// "70%", "2700 K".
    func text(_ value: Double) -> String {
        switch self {
        case .volume: return "\(Int((value * 100).rounded()))%"
        case .colorTemp: return "\(Int(value.rounded())) K"
        case .brightness, .position, .tilt, .percentage: return "\(Int(value.rounded()))%"
        }
    }

    /// Which of an entity's sliders this is (`KhalaControlModel.slot`): a light's warmth beside its brightness, a
    /// cover's tilt beside its position, each with its own pending entry.
    var slot: String {
        switch self {
        case .colorTemp: return "warmth"
        case .tilt: return "tilt"
        case .brightness, .position, .volume, .percentage: return "slider"
        }
    }
}
