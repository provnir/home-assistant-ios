import SFSafeSymbols

/// One section of a device screen's bottom bar (Camera: Live · Events · Settings; Car: Overview · Climate ·
/// Charging; Hot water: Now · Schedule · History). DESIGN.md: bottom tabs only for these pre-known sections.
struct KhalaSubTab: Identifiable, Equatable {
    let title: String
    let symbol: SFSymbol

    var id: String { title }
}
