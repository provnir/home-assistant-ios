import Foundation

/// The "tad of color" families of the Khala design (DESIGN.md, Tokens): one muted accent per family, used only on
/// timeline dots, small glyph chips and active controls. Colour only — what a thing IS is its `KhalaKind`; every
/// kind borrows one of these (light → sun, climate → heat, lock → security, the rest neutral), so there are no
/// new hues (Nir, 2026-11-01).
///
/// Foundation-only on purpose (no SwiftUI): the colours themselves live in `KhalaTheme`. The raw values are
/// persisted (`KhalaRoleAssignment`), so they never change.
enum KhalaAccent: String, Codable, CaseIterable, Equatable {
    /// Cameras and security.
    case security
    case car
    /// Water heaters, boilers, climate and other heat sources.
    case heat
    /// Theater, speakers and other media players.
    case media
    /// Sunrise and sunset; lights borrow it.
    case sun
    /// Anything else (plugs, relays, covers, fans, unclassified automations).
    case neutral
}
