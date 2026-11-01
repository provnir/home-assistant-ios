import Foundation

/// One control on any surface — device screens, the car's tabs, the generic screen, the media sheet, Now chips —
/// as the single grid of slice 2 will draw it (DESCRIPTORS-DESIGN.md §2). Slice 1 defines the shape only; today's
/// tiles still come from `KhalaControl`. The optimistic `pending` overlay joins with `KhalaPendingStore` in slice 2.
struct KhalaControlModel: Identifiable, Equatable {
    enum Kind: Equatable {
        case toggle(isOn: Bool)
        /// The current value, 0...100 (volume 0...1 as HA reports it); nil when unknown.
        case slider(KhalaSlider, value: Double?)
        case stepper(KhalaNumberSetting)
        case choice(current: String?, options: [String], field: KhalaChoiceField)
        case press
        /// `canOpen` from `LockCapabilities.supportsOpen`.
        case lock(isLocked: Bool, canOpen: Bool)
        case commands([KhalaCommand])
    }

    let entityId: String
    /// `KhalaEntity.nameWithoutDevice`: HA's own, already localised name.
    let title: String
    let symbol: KhalaGlyph
    let kind: Kind
    let confirm: KhalaConfirm?

    var id: String { entityId }
}
