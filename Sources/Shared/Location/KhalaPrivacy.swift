import Foundation

/// Khala build switch: this fork never tracks the phone (Nir's standing rule; presence comes from the car).
///
/// The upstream location machinery stays in the source, so rebases onto upstream stay clean; each place that
/// would ask for location permission, read a fix, monitor regions or significant changes, or report the
/// location (or a network identity that stands in for it) checks one of these switches first. Flip them to
/// `true` to get upstream's behaviour back.
///
/// What is gated (see `SCREENS-IMPL.md` in the Khala notes for the list with file names):
/// - permission prompts: `LocationManager`, `Permissions`, onboarding, Location settings, server switching;
/// - fixes: `CLLocationManager.oneShotLocation`, the flight-greetings speed probe;
/// - monitoring: `SettingsStore.locationSources` reads all-off, so `ZoneManager` stops significant-change
///   monitoring and removes every monitored zone/beacon region it finds (also those left by an earlier build);
///   background location is never allowed;
/// - reporting: `HomeAssistantAPI.SubmitLocation` sends sensors only, never `update_location`;
///   `SettingsStore.isLocationEnabled` is false; the Geocoded Location sensor is not registered;
///   the SSID and BSSID sensors are not reported;
/// - settings UI: the Location settings entry is hidden.
public enum KhalaPrivacy {
    /// The phone's location is read, monitored or reported.
    public static let reportsLocation = false
    /// Network identities that locate the phone (Wi-Fi SSID/BSSID) are reported as sensors.
    public static let reportsNetworkIdentity = false
}
