import Foundation

/// What a kind's main control does when tapped (DESCRIPTORS-DESIGN.md §1).
enum KhalaPrimaryAction: String, Equatable {
    case toggle
    case press
    case lock
    case open
    case none
}
