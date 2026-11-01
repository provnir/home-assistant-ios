import Foundation
import Shared

/// The cover hero (DESCRIPTORS-DESIGN.md §3, "Cover"): Open / Stop / Close as the cover supports them
/// (`CoverCapabilities`), a position slider when it can be set, and its tilt — a slider when the tilt position can
/// be set, else tilt Open / Stop / Close. Opening a garage door, a gate, a door or a cover that doesn't say what it
/// is asks first, by any route — the Open button or a higher position (`KhalaConfirmPolicy`).
struct KhalaCoverPanel: Equatable {
    /// `CoverEntityFeature` tilt bits Home Assistant's `CoverCapabilities` doesn't parse.
    private enum TiltFeature: Int {
        case open = 16
        case close = 32
        case stop = 64
        case setPosition = 128
    }

    let entityId: String
    /// "Open · 100%", "Closed", "Opening".
    let subtitle: String
    /// Commands first, then position, then tilt.
    let controls: [KhalaControlModel]

    init(entity: KhalaEntity, attributes: [String: Any]) {
        let capabilities = CoverCapabilities(attributes: attributes)
        let features = KhalaValue.int(attributes["supported_features"]) ?? 0
        let available = !entity.isUnavailable
        let position = KhalaValue.double(attributes["current_position"])
        entityId = entity.entityId

        func make(_ title: String, symbol: String, kind: KhalaControlModel.Kind) -> KhalaControlModel {
            make(title, glyph: .sf(symbol), kind: kind)
        }

        func make(_ title: String, glyph: KhalaGlyph, kind: KhalaControlModel.Kind) -> KhalaControlModel {
            var control = KhalaControlModel(entityId: entity.entityId, title: title, symbol: glyph, kind: kind,
                                            confirm: nil)
            control.deviceClass = entity.deviceClass
            control.isAvailable = available
            return control
        }

        var controls: [KhalaControlModel] = []
        let commands: [KhalaCommand] = [
            capabilities.supportsOpen ? .open : nil,
            capabilities.supportsStop ? .stop : nil,
            capabilities.supportsClose ? .close : nil,
        ].compactMap { $0 }
        if !commands.isEmpty {
            // Titled with the cover's own name, so the question reads "Open garage door?".
            // The menu's glyph for this cover (`KhalaIconChain`): garage, door, window… by device class.
            var control = make(entity.name, glyph: KhalaIconChain.cover(entity), kind: .commands(commands))
            control.stateText = KhalaText.humanized(state: entity.state)
            // As Home Assistant's own card: no Open once fully open (or opening), no Close once closed (or closing).
            let fullyOpen = position.map { $0 >= 100 } ?? (entity.state == "open")
            control.directions = .init(on: entity.state != "opening" && !fullyOpen,
                                       off: entity.state != "closing" && entity.state != "closed")
            controls.append(control)
        }
        if capabilities.supportsSetPosition {
            var control = make(KhalaScreenText.coverPosition, symbol: "arrow.up.and.down",
                               kind: .slider(.position, value: position))
            control.stateText = position.map { KhalaSlider.position.text($0) } ?? ""
            controls.append(control)
        }
        let tilt = KhalaValue.double(attributes["current_tilt_position"])
        if features & TiltFeature.setPosition.rawValue != 0 {
            var control = make(KhalaScreenText.tilt, symbol: "line.3.horizontal", kind: .slider(.tilt, value: tilt))
            control.stateText = tilt.map { KhalaSlider.tilt.text($0) } ?? ""
            controls.append(control)
        } else {
            let tiltCommands: [KhalaCommand] = [
                features & TiltFeature.open.rawValue != 0 ? .openTilt : nil,
                features & TiltFeature.stop.rawValue != 0 ? .stopTilt : nil,
                features & TiltFeature.close.rawValue != 0 ? .closeTilt : nil,
            ].compactMap { $0 }
            if !tiltCommands.isEmpty {
                controls.append(make(KhalaScreenText.tilt, symbol: "line.3.horizontal", kind: .commands(tiltCommands)))
            }
        }
        self.controls = controls

        var parts = [KhalaText.humanized(state: entity.state)]
        if available, let position, capabilities.supportsSetPosition {
            parts.append(KhalaSlider.position.text(position))
        }
        subtitle = parts.joined(separator: " · ")
    }
}
