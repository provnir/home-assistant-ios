import Foundation

/// A service that turns an entity on for a number of minutes (`KhalaIntent.timedOn`), from the hints file.
struct KhalaTimedOn: Equatable {
    /// The service's domain (the integration's own, e.g. a vendor service).
    let domain: String
    let service: String
    /// The data field that carries the duration.
    let field: String
    /// The field's unit: `min` (the default) or `s`.
    let unit: String

    /// The duration value to send for `minutes`.
    func value(minutes: Int) -> Int {
        unit == "s" ? minutes * 60 : minutes
    }
}
