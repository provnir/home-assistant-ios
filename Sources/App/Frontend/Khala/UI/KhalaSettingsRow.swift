import SFSafeSymbols
import SwiftUI

/// One row of a Settings card (mockup `DaySettings`): a 30 pt glyph chip, the title, an optional figure or
/// attention chip, and a chevron; 52 pt tall, a hairline under every row but the last.
struct KhalaSettingsRow: View {
    enum Style {
        /// A Home Assistant settings page: the security blue on its tint.
        case server
        /// One of the app's own settings: ink on a neutral chip.
        case app
    }

    let title: String
    var subtitle: String?
    let glyph: KhalaSettingsGlyph
    let style: Style
    var figure: String?
    var attention: String?
    var showsDivider = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemSymbol: KhalaSettingsSymbols.symbol(glyph))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(style == .server ? KhalaTheme.accent(.security) : KhalaTheme.ink)
                    .frame(width: 30, height: 30)
                    .background(
                        style == .server ? KhalaTheme.tint(.security) : KhalaTheme.appChip,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 16))
                        .foregroundStyle(KhalaTheme.ink)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(KhalaTheme.secondaryText)
                            .foregroundStyle(KhalaTheme.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let attention {
                    KhalaAttentionChip(text: attention, showsDot: false, height: 22)
                } else if let figure {
                    Text(figure)
                        .font(.system(size: 15))
                        .foregroundStyle(KhalaTheme.muted)
                }
                Image(systemSymbol: .chevronRight)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KhalaTheme.chevron)
                    .accessibilityHidden(true)
            }
            .padding(.trailing, 14)
            .frame(minHeight: 52)
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Rectangle()
                        .fill(KhalaTheme.rowDivider)
                        .frame(height: 0.5)
                        .padding(.leading, 42)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(KhalaRowPressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// A row's press: the row dims a touch while held, as a list cell highlights.
struct KhalaRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A solid white card of settings rows (mockup: 24 pt corners, 14 pt leading inset, the content-card shadow).
struct KhalaSettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.leading, 14)
        .padding(.vertical, 4)
        .background(KhalaTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .khalaCardShadow()
    }
}

#Preview {
    KhalaSettingsCard {
        KhalaSettingsRow(title: "Devices & services", glyph: .devices, style: .server) {}
        KhalaSettingsRow(title: "Automations & scenes", glyph: .automations, style: .server, figure: "3") {}
        KhalaSettingsRow(title: "System", glyph: .system, style: .server, attention: "1 update") {}
        KhalaSettingsRow(title: "Notifications", glyph: .notifications, style: .app, showsDivider: false) {}
    }
    .padding()
    .background(KhalaGround())
}
