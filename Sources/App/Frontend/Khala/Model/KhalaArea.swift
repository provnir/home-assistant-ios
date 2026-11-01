import Foundation

/// A Home Assistant area as the menu groups devices by it (decision 1): id, display name and HA's own sort order.
struct KhalaArea: Equatable, Identifiable {
    let id: String
    let name: String
    /// The order the user gave the areas in Home Assistant; nil sorts by name after the ordered ones.
    var sortOrder: Int?
}
