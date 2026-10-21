import SFSafeSymbols

/// The SF Symbol for each Settings glyph (`KhalaSettingsGlyph`). Names checked against SFSafeSymbols 5.3.0
/// (symbol sets 1.0–3.0, so iOS 16.4 has them all).
enum KhalaSettingsSymbols {
    static func symbol(_ glyph: KhalaSettingsGlyph) -> SFSymbol {
        switch glyph {
        case .cloud: return .icloud
        case .devices: return .powerplug
        case .automations: return .gearshape2
        case .areas: return .house
        case .apps: return .puzzlepiece
        case .dashboards: return .squareGrid2x2
        case .connectivity: return .antennaRadiowavesLeftAndRight
        case .voice: return .mic
        case .people: return .person2
        case .system: return .gearshape
        case .tools: return .hammer
        case .about, .appAbout: return .infoCircle
        case .integrations: return .puzzlepieceExtension
        case .entities: return .squareStack3dUp
        case .helpers: return .wrenchAndScrewdriver
        case .scenes: return .paintpalette
        case .scripts: return .scroll
        case .blueprints: return .docText
        case .labels: return .tag
        case .zones: return .mappin
        case .users: return .personCropCircle
        case .tags: return .wave3Right
        case .general: return .mappinAndEllipse
        case .updates: return .arrowDownCircle
        case .repairs: return .bandage
        case .logs: return .docPlaintext
        case .backups: return .clockArrowCirclepath
        case .network: return .network
        case .storage: return .internaldrive
        case .hardware: return .memorychip
        case .analytics: return .chartBar
        case .labs: return .testtube2
        case .radio: return .dotRadiowavesLeftAndRight
        case .servers: return .serverRack
        case .appGeneral: return .sliderHorizontal3
        case .gestures: return .handTap
        case .notifications: return .bell
        case .liveActivities: return .playRectangle
        case .kiosk: return .display
        case .privacy: return .handRaised
        case .more: return .ellipsisCircle
        case .page: return .doc
        }
    }
}
