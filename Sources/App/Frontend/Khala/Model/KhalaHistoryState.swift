import Foundation

/// One recorded state of an entity, from Home Assistant's `history/history_during_period` answer.
struct KhalaHistoryState: Equatable {
    let state: String
    /// When the state was recorded (`lu`, last updated).
    let date: Date
    /// `event.*` only: the `event_type` attribute, when attributes were sent.
    let eventType: String?
}
