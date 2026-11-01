import Foundation

/// A kind of thing Khala knows how to show (DESCRIPTORS-DESIGN.md §1): types are code (this, and the table in
/// `KhalaDescriptors`); which entity is which is data. The controls recipe and the screen template join in later
/// slices; slice 1 carries what detection, colour and ordering need.
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
}
