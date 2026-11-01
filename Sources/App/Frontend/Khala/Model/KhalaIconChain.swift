import Foundation

/// Which glyph a device or a control draws (DESCRIPTORS-DESIGN.md §4 row 6, decision 4: SF Symbols first, HA's own
/// icon as the fallback). Every step reads registry facts, device class, domain and state; names and ids never.
///
/// 1. **Khala's SF Symbol**, when Khala knows what the thing is: a hint's glyph (the car's and the boiler's tiles,
///    `khala-hints.json`, always first), the kind's designed glyph (car, hot water, media, climate, light, fan,
///    camera, lock by its state), a cover by its device class (garage, door, window, shade…).
/// 2. **Home Assistant's icon**, for everything else: the registry icon the user set, else HA's own state-aware
///    resolution (`KhalaEntity.haIcon`). Drawn as the SF Symbol of the same meaning when `KhalaMDISymbols` has
///    one, else as HA's MDI glyph.
/// 3. **The domain default**: Khala's glyph for the domain, else the kind's fallback symbol.
enum KhalaIconChain {
    /// A device's glyph in the menu's DEVICES list and on the Now card's chips, from its kind and face entity.
    static func device(kind: KhalaKind, face: KhalaEntity?) -> KhalaGlyph {
        if let face, kind == .cover || (kind == .generic && face.domain == "cover") {
            return cover(face)
        }
        if let symbol = kindSymbol(kind, face: face) { return .sf(symbol) }
        if let face, let glyph = haGlyph(face) { return glyph }
        return domainDefault(face?.domain) ?? .sf(kind.descriptor.fallbackSymbol)
    }

    /// A control tile's glyph: the tile's own Khala glyph (hint, lock state, domain) when it has one; a tile Khala
    /// only has the generic glyph for goes down the chain (a cover by device class, then HA's icon).
    static func tile(_ control: KhalaControl, entity: KhalaEntity) -> KhalaGlyph {
        guard control.glyph == .generic else { return .sf(control.glyph.symbolName) }
        if entity.domain == "cover" { return cover(entity) }
        return haGlyph(entity) ?? .sf(control.glyph.symbolName)
    }

    /// A control tile's own Khala glyph (`KhalaControl.make`): a lock's state, else its hint's glyph
    /// (`KhalaHints`, keyed on platform and translation key), else its device class and domain.
    static func tileGlyph(for entity: KhalaEntity, hints: KhalaHints = .builtIn) -> KhalaControl.Glyph {
        if entity.domain == "lock" { return entity.state == "locked" ? .lock : .unlock }
        if let glyph = hints.hint(for: entity)?.glyph { return glyph }
        if entity.deviceClass == "window" { return .window }
        switch entity.domain {
        case "light": return .lights
        case "fan", "climate": return .fan
        case "button": return .button
        case "switch": return .power
        default: return .generic
        }
    }

    /// A cover's glyph: an SF Symbol for the device classes that have one, open or closed; else HA's icon; else a
    /// gate's MDI glyph (SF has no gate) or blinds.
    static func cover(_ entity: KhalaEntity) -> KhalaGlyph {
        let open = isOpen(entity)
        if let symbol = coverSymbol(deviceClass: entity.deviceClass, isOpen: open) { return .sf(symbol) }
        if let glyph = haGlyph(entity) { return glyph }
        if entity.deviceClass == "gate" { return .mdi(open ? "mdi:gate-open" : "mdi:gate") }
        return .sf(open ? "blinds.horizontal.open" : "blinds.horizontal.closed")
    }

    /// The SF Symbol of a cover device class, open or closed; nil for the classes SF has no symbol for (gate,
    /// damper) and for a cover that doesn't say what it is.
    static func coverSymbol(deviceClass: String?, isOpen: Bool) -> String? {
        switch deviceClass {
        case "garage": return isOpen ? "door.garage.open" : "door.garage.closed"
        case "door": return isOpen ? "door.left.hand.open" : "door.left.hand.closed"
        case "window": return isOpen ? "window.vertical.open" : "window.vertical.closed"
        case "shutter", "shade": return isOpen ? "window.shade.open" : "window.shade.closed"
        case "blind": return isOpen ? "blinds.horizontal.open" : "blinds.horizontal.closed"
        case "curtain": return isOpen ? "curtains.open" : "curtains.closed"
        case "awning": return "window.awning"
        default: return nil
        }
    }

    /// HA's icon for `entity` (step 2), as an SF Symbol of the same meaning when there is one, else as MDI.
    static func haGlyph(_ entity: KhalaEntity) -> KhalaGlyph? {
        guard let icon = entity.haIcon, !icon.isEmpty else { return nil }
        if let symbol = KhalaMDISymbols.sfSymbol(forMDI: icon) { return .sf(symbol) }
        return .mdi(icon.hasPrefix("mdi:") ? icon : "mdi:" + icon)
    }

    // MARK: - Private

    /// The designed glyph of a kind Khala draws its own way (step 1); nil for switches, vacuums, generic and
    /// unknown kinds, which take HA's icon. Car, hot water, media and camera keep the glyph 41.1 drew for them.
    private static func kindSymbol(_ kind: KhalaKind, face: KhalaEntity?) -> String? {
        switch kind {
        case .lock:
            return ["unlocked", "open", "opening"].contains(face?.state ?? "") ? "lock.open" : "lock"
        case .car, .waterHeater, .media, .camera, .climate, .fan, .light, .lightGroup:
            return kind.descriptor.fallbackSymbol
        default:
            return nil
        }
    }

    /// Khala's glyph for a domain when neither Khala's kind nor HA names one (step 3).
    private static func domainDefault(_ domain: String?) -> KhalaGlyph? {
        switch domain {
        case "light": return .sf("lightbulb")
        case "fan": return .sf("fanblades")
        case "climate": return .sf("thermometer.medium")
        case "water_heater": return .sf("drop")
        case "media_player": return .sf("tv")
        case "camera": return .sf("video")
        case "lock": return .sf("lock")
        case "switch": return .sf("powerplug")
        case "input_boolean": return .sf("switch.2")
        case "button", "input_button": return .sf("circle.circle")
        case "vacuum": return .mdi("mdi:robot-vacuum")
        case "lawn_mower": return .mdi("mdi:robot-mower")
        case "valve": return .sf("spigot")
        case "humidifier": return .sf("humidifier")
        case "siren": return .sf("light.beacon.max")
        case "scene": return .sf("paintpalette")
        case "script": return .sf("scroll")
        case "device_tracker", "person": return .sf("person")
        default: return nil
        }
    }

    /// Open, opening or closing (still open until it is closed).
    private static func isOpen(_ entity: KhalaEntity) -> Bool {
        ["open", "opening", "closing"].contains(entity.state)
    }
}
