import Foundation

/// A kind of thing Khala knows how to show (DESCRIPTORS-DESIGN.md §1): types are code (this, and the table in
/// `KhalaDescriptors`); which entity is which is data. It carries what detection, colour, ordering and the
/// template screen need; the controls recipe joins in a later slice.
struct KhalaDescriptor: Equatable {
    let kind: KhalaKind
    let accent: KhalaAccent
    let match: KhalaMatch
    /// nil = this kind never names a whole device (cameras: routing only; the generic fallback).
    let deviceRule: KhalaDeviceRule?
    let primary: KhalaPrimaryAction
    /// Device precedence and Now-chip order, highest first.
    let priority: Int
    /// SF Symbol name, used only after the icon chain (registry icon, hint, HA's own icon resolution).
    let fallbackSymbol: String
    /// The screen `KhalaTemplateScreen` draws for this kind (slice 3: lights and fans; the rest generic).
    var template: KhalaTemplateSpec = .generic
    /// Where a device of this kind opens: the routing table (`KhalaScreenRoute`).
    var route: KhalaScreenRoute = .template
}
