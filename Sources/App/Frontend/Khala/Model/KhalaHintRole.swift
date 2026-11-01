import Foundation

/// What a hinted entity is to the screen that reads it.
enum KhalaHintRole: String, Equatable {
    // Car readings.
    case battery
    case range
    case chargingState = "charging_state"
    case chargerPower = "charger_power"
    case timeToFull = "time_to_full"
    case chargeLimit = "charge_limit"
    case chargeCurrent = "charge_current"
    case location
    case insideTemperature = "inside_temperature"
    case outsideTemperature = "outside_temperature"
    /// The button that wakes a sleeping car (pressed before every read and command).
    case wake
    /// The sensor that says whether the car is awake (on = online).
    case connectivity
    // Hot water.
    /// Time left on the device's own timer.
    case remaining
    /// A role this build doesn't know (a newer hints file): read as no role.
    case unknown
}
