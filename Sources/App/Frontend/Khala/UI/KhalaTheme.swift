import SFSafeSymbols
import SwiftUI
import UIKit

/// Khala design tokens (notes/ha-ios/DESIGN.md "Tokens"): neutral ground, white solid cards, ink text and one muted
/// accent per category. Light values are the approved mockup's; dark values are this file's own, chosen to keep the
/// same calm contrast.
enum KhalaTheme {
    // MARK: - Colours

    static let ink = dynamic(light: 0x15171C, dark: 0xF2F1EE)
    static let secondary = dynamic(light: 0x5D6068, dark: 0xA9ABB1)
    /// Card subtitles.
    static let tertiary = dynamic(light: 0x6B6E75, dark: 0x9A9CA3)
    static let muted = dynamic(light: 0x8A8C92, dark: 0x7E8087)
    static let line = dynamic(light: 0xDCD9D2, dark: 0x3A3B40)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1F2126)
    /// Flat ground, also the fill of outlined (upcoming) dots.
    static let groundFlat = dynamic(light: 0xF3F2EF, dark: 0x121316)
    static let groundTop = dynamic(light: 0xF7F3EC, dark: 0x17181C)
    static let groundBottom = dynamic(light: 0xEEF0F2, dark: 0x0F1013)
    static let menuTop = dynamic(light: 0xECE7DE, dark: 0x1B1C20)
    static let menuMiddle = dynamic(light: 0xE7E5DF, dark: 0x18191D)
    static let menuBottom = dynamic(light: 0xE2E4E7, dark: 0x141518)
    /// Placeholder fill of an event thumbnail.
    static let thumbnail = dynamic(light: 0xC3CCD9, dark: 0x3A4352)
    /// Warm glow (top) and cool glow (bottom) of the ground wash.
    static let warmGlow = Color(red: 242 / 255, green: 176 / 255, blue: 97 / 255)
    static let coolGlow = Color(red: 74 / 255, green: 111 / 255, blue: 165 / 255)
    static let shadow = Color(red: 20 / 255, green: 20 / 255, blue: 30 / 255)
    /// Text of the amber attention chip (updates, repairs).
    static let attentionInk = dynamic(light: 0x8A4A10, dark: 0xF0B47A)
    /// Hairlines between rows of a settings card.
    static let rowDivider = dynamic(light: 0xE6E3DC, dark: 0x2E3035)
    /// A settings row's trailing chevron.
    static let chevron = dynamic(light: 0xB4B4BC, dark: 0x5E6067)
    /// The glyph chip of an app settings row.
    static let appChip = dynamic(light: 0xEFEDEA, dark: 0x2A2B30)

    /// A timeline line stretch's colour: ink through the past, the light line through what's coming, none past an end.
    static func stroke(_ stroke: KhalaTimelineStroke) -> Color? {
        switch stroke {
        case .none: return nil
        case .upcoming: return line
        case .past: return ink
        }
    }

    static func accent(_ category: KhalaCategory) -> Color {
        switch category {
        case .security: return dynamic(light: 0x4A6FA5, dark: 0x86A5D6)
        case .car: return dynamic(light: 0x2F8F83, dark: 0x5DC0B2)
        case .heat: return dynamic(light: 0xC7782A, dark: 0xE39B55)
        case .media: return dynamic(light: 0x7564B3, dark: 0xA193DC)
        case .sun: return dynamic(light: 0xC9952E, dark: 0xE2B756)
        case .neutral: return dynamic(light: 0x5D6068, dark: 0xA9ABB1)
        }
    }

    static func tint(_ category: KhalaCategory) -> Color {
        switch category {
        case .security: return dynamic(light: 0xE6EDF7, dark: 0x243042)
        case .car: return dynamic(light: 0xE9F3F1, dark: 0x1E3532)
        case .heat: return dynamic(light: 0xFBF0E3, dark: 0x3B2C1C)
        case .media: return dynamic(light: 0xEFECF8, dark: 0x2D2842)
        case .sun: return dynamic(light: 0xFAF2DE, dark: 0x3A321C)
        case .neutral: return dynamic(light: 0xF3F2EF, dark: 0x2A2B30)
        }
    }

    // MARK: - Type (SF Pro, system)

    static let largeTitle = Font.system(size: 34, weight: .bold)
    static let headerSubtitle = Font.system(size: 15, weight: .medium)
    static let cardTitle = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 15)
    static let secondaryText = Font.system(size: 13)
    static let time = Font.system(size: 13, weight: .semibold).monospacedDigit()
    static let timeNow = Font.system(size: 13, weight: .bold)
    static let chipValue = Font.system(size: 17, weight: .semibold)
    static let chipLabel = Font.system(size: 11, weight: .semibold)
    static let menuRow = Font.system(size: 16)
    static let menuRowSelected = Font.system(size: 16, weight: .semibold)
    static let menuTrailing = Font.system(size: 14)
    static let caption = Font.system(size: 12, weight: .bold)

    // MARK: - Metrics

    static let gutter: CGFloat = 20
    static let timeColumn: CGFloat = 44
    /// From the time column to the content: the dot sits centred in it.
    static let dotColumn: CGFloat = 23
    static let contentInset: CGFloat = 9
    static let rowGap: CGFloat = 18
    static let lineWidth: CGFloat = 1.5

    // MARK: - Glyphs

    static func symbol(_ category: KhalaCategory) -> SFSymbol {
        switch category {
        case .security: return .video
        case .car: return .car
        case .heat: return .drop
        case .media: return .tv
        case .sun: return .sunMaxFill
        case .neutral: return .powerplug
        }
    }

    static func symbol(_ destination: KhalaDestination) -> SFSymbol {
        switch destination {
        case .today: return .textAlignleft
        case .cameras, .camera: return .video
        case .device, .entity: return .powerplug
        case .automations: return .wandAndStars
        case .dashboards: return .squareGrid2x2
        case .settings: return .gearshape
        }
    }

    // MARK: - Private

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? uiColor(dark) : uiColor(light)
        })
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// The solid content-card shadow: `0 1 2 /5%` + `0 8 24 /6%`, or `0 12 30 /8%` for the lifted Now card.
    func khalaCardShadow(lifted: Bool = false) -> some View {
        shadow(color: KhalaTheme.shadow.opacity(0.05), radius: 1, x: 0, y: 1)
            .shadow(
                color: KhalaTheme.shadow.opacity(lifted ? 0.08 : 0.06),
                radius: lifted ? 15 : 12,
                x: 0,
                y: lifted ? 12 : 8
            )
    }
}
