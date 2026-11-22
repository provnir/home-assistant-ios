import Foundation
@testable import HomeAssistant
import Testing

struct KhalaPushRelayTests {
    @Test func onlyAnHTTPSURLTurnsTheRelayOn() {
        #expect(KhalaPushRelay.url(info: [:]) == nil)
        #expect(KhalaPushRelay.url(info: [KhalaPushRelay.infoKey: ""]) == nil)
        #expect(KhalaPushRelay.url(info: [KhalaPushRelay.infoKey: "http://relay.example/s/sendPushNotification"]) == nil)
        let url = KhalaPushRelay.url(info: [KhalaPushRelay.infoKey: "https://relay.example/s/sendPushNotification"])
        #expect(url?.host == "relay.example")
    }
}
