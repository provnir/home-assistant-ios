import Foundation

/// Material Design icon → SF Symbol (decision 4, "SF Symbols first, HA's own icon only when there's no match"):
/// when Home Assistant names an icon for an entity (the user's registry icon, or HA's own state-aware resolution),
/// Khala draws the SF Symbol that means the same thing, so the system look stays consistent; an icon with no entry
/// here is drawn as HA's own MDI glyph.
///
/// Keys are MDI names without the `mdi:` prefix. Values are SF Symbols that ship with iOS 16 (SF Symbols 4.0), the
/// app's deployment floor, so none of them draws blank on an older phone. The table maps meaning, not shapes: an
/// MDI icon with no SF Symbol of the same meaning (a gate, a robot vacuum, a robot) is left out on purpose.
enum KhalaMDISymbols {
    /// The SF Symbol for `icon` (`mdi:garage-open` or `garage-open`), or nil when none means the same thing.
    static func sfSymbol(forMDI icon: String) -> String? {
        let name = icon.hasPrefix("mdi:") ? String(icon.dropFirst(4)) : icon
        if let symbol = table[name] { return symbol }
        return battery(name)
    }

    /// `battery-10` … `battery-90` (HA's battery range icons) to the nearest SF battery level.
    private static func battery(_ name: String) -> String? {
        let parts = name.split(separator: "-")
        guard parts.count == 2, parts[0] == "battery", let level = Int(parts[1]) else { return nil }
        switch level {
        case ..<20: return "battery.0"
        case ..<45: return "battery.25"
        case ..<70: return "battery.50"
        case ..<95: return "battery.75"
        default: return "battery.100"
        }
    }

    static let table: [String: String] = [
        // Lights
        "lightbulb": "lightbulb",
        "lightbulb-on": "lightbulb.fill",
        "lightbulb-off": "lightbulb",
        "lightbulb-outline": "lightbulb",
        "lightbulb-group": "lightbulb.2",
        "lightbulb-group-off": "lightbulb.2",
        "ceiling-light": "lamp.ceiling",
        "floor-lamp": "lamp.floor",
        "desk-lamp": "lamp.desk",
        "lamp": "lamp.table",
        "chandelier": "chandelier",
        "light-recessed": "light.recessed",
        "light-switch": "lightswitch.on",
        "alarm-light": "light.beacon.max",
        // Switches and power
        "toggle-switch": "switch.2",
        "toggle-switch-off": "switch.2",
        "toggle-switch-variant": "switch.2",
        "toggle-switch-variant-off": "switch.2",
        "toggle-switch-outline": "switch.2",
        "toggle-switch-off-outline": "switch.2",
        "power-plug": "powerplug",
        "power-plug-off": "powerplug",
        "power-socket": "powerplug",
        "power": "power",
        "power-off": "power",
        "flash": "bolt",
        "flash-off": "bolt.slash",
        "lightning-bolt": "bolt",
        // Fans and air
        "fan": "fanblades",
        "fan-off": "fanblades",
        "ceiling-fan": "fan.ceiling",
        "air-conditioner": "air.conditioner.horizontal",
        "hvac": "air.conditioner.horizontal",
        "air-humidifier": "humidifier",
        "air-humidifier-off": "humidifier",
        "air-purifier": "air.purifier",
        "air-filter": "air.purifier",
        // Heat and water
        "thermostat": "thermometer.medium",
        "thermometer": "thermometer.medium",
        "home-thermometer": "thermometer.medium",
        "radiator": "heater.vertical",
        "fire": "flame",
        "fireplace": "fireplace",
        "snowflake": "snowflake",
        "water-boiler": "drop",
        "water-boiler-off": "drop",
        "water": "drop",
        "water-off": "drop",
        "water-percent": "humidity",
        "valve": "spigot",
        "valve-open": "spigot",
        "valve-closed": "spigot",
        "pipe-valve": "spigot",
        "sprinkler": "sprinkler.and.droplets",
        "sprinkler-variant": "sprinkler.and.droplets",
        // Covers (gates have no SF Symbol: HA's own glyph is drawn)
        "garage": "door.garage.closed",
        "garage-variant": "door.garage.closed",
        "garage-open": "door.garage.open",
        "garage-open-variant": "door.garage.open",
        "door": "door.left.hand.closed",
        "door-closed": "door.left.hand.closed",
        "door-open": "door.left.hand.open",
        "door-sliding": "door.sliding.right.hand.closed",
        "door-sliding-open": "door.sliding.right.hand.open",
        "window-closed": "window.vertical.closed",
        "window-closed-variant": "window.vertical.closed",
        "window-open": "window.vertical.open",
        "window-open-variant": "window.vertical.open",
        "window-shutter": "window.shade.closed",
        "window-shutter-open": "window.shade.open",
        "blinds": "blinds.horizontal.closed",
        "blinds-horizontal-closed": "blinds.horizontal.closed",
        "blinds-horizontal": "blinds.horizontal.open",
        "blinds-open": "blinds.horizontal.open",
        "roller-shade": "roller.shade.open",
        "roller-shade-closed": "roller.shade.closed",
        "curtains": "curtains.open",
        "curtains-closed": "curtains.closed",
        "awning": "window.awning",
        "awning-outline": "window.awning",
        // Locks and security
        "lock": "lock.fill",
        "lock-outline": "lock.fill",
        "lock-open": "lock.open.fill",
        "lock-open-variant": "lock.open.fill",
        "lock-open-outline": "lock.open.fill",
        "shield": "shield",
        "shield-home": "lock.shield",
        "shield-lock": "lock.shield",
        "shield-check": "checkmark.shield",
        "shield-off": "shield.slash",
        "bell": "bell",
        "bell-ring": "bell",
        "doorbell": "bell",
        "doorbell-video": "video.doorbell",
        "cctv": "video",
        "video": "video",
        "camera": "camera",
        "webcam": "web.camera",
        "motion-sensor": "figure.walk",
        "walk": "figure.walk",
        "smoke-detector": "smoke",
        "molecule-co2": "carbon.dioxide.cloud",
        "molecule-co": "carbon.monoxide.cloud",
        "eye": "eye",
        "eye-off": "eye.slash",
        "key": "key",
        // Media
        "television": "tv",
        "television-off": "tv",
        "television-classic": "tv",
        "speaker": "hifispeaker",
        "speaker-off": "hifispeaker",
        "music": "music.note",
        "music-note": "music.note",
        // People and places
        "account": "person",
        "home": "house",
        "home-outline": "house",
        "map-marker": "mappin",
        "map-marker-radius": "mappin.and.ellipse",
        "crosshairs-gps": "location",
        "earth": "globe",
        // Vehicles
        "car": "car",
        "car-electric": "bolt.car",
        // Appliances
        "washing-machine": "washer",
        "tumble-dryer": "dryer",
        "dishwasher": "dishwasher",
        "fridge": "refrigerator",
        "fridge-outline": "refrigerator",
        "stove": "stove",
        "microwave": "microwave",
        "toaster-oven": "oven",
        "coffee-maker": "cup.and.saucer",
        "printer": "printer",
        // Network and devices
        "wifi": "wifi",
        "access-point": "wifi",
        "router-wireless": "wifi.router",
        "server": "server.rack",
        "desktop-classic": "desktopcomputer",
        "laptop": "laptopcomputer",
        "cellphone": "iphone",
        "tablet": "ipad",
        "watch": "applewatch",
        // Readings
        "gauge": "gauge",
        "battery": "battery.100",
        "battery-outline": "battery.0",
        "battery-charging": "battery.100.bolt",
        "weather-sunny": "sun.max",
        "white-balance-sunny": "sun.max",
        "weather-night": "moon",
        "weather-cloudy": "cloud",
        "weather-rainy": "cloud.rain",
        "weather-windy": "wind",
        "leaf": "leaf",
        "ruler": "ruler",
        "scale-bathroom": "scalemass",
        "weight": "scalemass",
        // Time
        "clock": "clock",
        "clock-outline": "clock",
        "timer": "timer",
        "timer-outline": "timer",
        "calendar": "calendar",
        "calendar-clock": "calendar.badge.clock",
        // Actions and helpers
        "button-pointer": "circle.circle",
        "gesture-tap-button": "hand.tap",
        "restart": "arrow.clockwise",
        "update": "arrow.down.circle",
        "package": "shippingbox",
        "package-up": "shippingbox",
        "package-down": "shippingbox",
        "format-list-bulleted": "list.bullet",
        "script-text": "scroll",
        "palette": "paintpalette",
        // Home
        "bed": "bed.double",
        "sofa": "sofa",
        "paw": "pawprint",
    ]
}
