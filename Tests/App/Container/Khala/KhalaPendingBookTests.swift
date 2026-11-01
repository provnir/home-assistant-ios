import Foundation
@testable import HomeAssistant
import Testing

/// The optimistic-state machine: success, failure revert, timeout, double-tap throttle.
struct KhalaPendingBookTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let key = "switch.a#power"

    private func entity(_ state: String, _ id: String = "switch.a") -> [String: KhalaEntity] {
        [id: KhalaScreenFixtures.entity(id, state)]
    }

    @Test func successSettlesOnTheEcho() {
        var book = KhalaPendingBook()
        do {
            let result = book.begin(key, entityId: "switch.a", value: .on(true), echo: .state(["on"]), now: t0)
            #expect(result)
        }
        #expect(book.pending(key)?.isInFlight == true)
        book.answer(key, startedAt: t0, ok: true, now: t0 + 0.3)
        #expect(book.pending(key)?.isInFlight == false)
        // Still off in HA: keep showing on.
        do {
            let result = book.reconcile(entities: entity("off"), attributes: [:], now: t0 + 1)
            #expect(!result)
        }
        #expect(book.pending(key)?.value == .on(true))
        // HA echoes: the entry steps aside for the real state.
        do {
            let result = book.reconcile(entities: entity("on"), attributes: [:], now: t0 + 1.5)
            #expect(result)
        }
        #expect(book.pending(key) == nil)
    }

    @Test func echoBeforeTheAnswerEndsItOnTheAnswer() {
        var book = KhalaPendingBook()
        _ = book.begin(key, entityId: "switch.a", value: .on(true), echo: .state(["on"]), now: t0)
        book.reconcile(entities: entity("on"), attributes: [:], now: t0 + 0.1)
        #expect(book.pending(key)?.isEchoed == true)
        book.answer(key, startedAt: t0, ok: true, now: t0 + 0.2)
        #expect(book.pending(key) == nil)
    }

    @Test func failureReverts() {
        var book = KhalaPendingBook()
        _ = book.begin(key, entityId: "switch.a", value: .on(true), echo: .state(["on"]), now: t0)
        book.answer(key, startedAt: t0, ok: false, now: t0 + 0.5)
        #expect(book.pending(key) == nil)
    }

    @Test func noEchoTimesOutAfterFiveSeconds() {
        var book = KhalaPendingBook()
        _ = book.begin(key, entityId: "switch.a", value: .on(true), echo: .state(["on"]), now: t0)
        // A car waking for 40 s: no timeout while the call is out.
        book.expire(now: t0 + 40)
        #expect(book.pending(key) != nil)
        book.answer(key, startedAt: t0, ok: true, now: t0 + 41)
        #expect(book.nextExpiry == t0 + 46)
        book.expire(now: t0 + 45.9)
        #expect(book.pending(key) != nil)
        book.expire(now: t0 + 46)
        #expect(book.pending(key) == nil)
        // A call never answered gives up too.
        _ = book.begin(key, entityId: "switch.a", value: .on(true), echo: .state(["on"]), now: t0 + 100)
        book.expire(now: t0 + 100 + KhalaPendingBook.inFlightLimit)
        #expect(book.pending(key) == nil)
    }

    @Test func doubleTapIsThrottled() {
        var book = KhalaPendingBook()
        do {
            let result = book.begin(key, entityId: "switch.a", value: .locked(false), echo: .state(["unlocked"]), now: t0)
            #expect(result)
        }
        // While out: refused.
        do {
            let result = book.begin(key, entityId: "switch.a", value: .locked(false), echo: .state(["unlocked"]),
                            now: t0 + 0.2)
            #expect(!result)
        }
        book.answer(key, startedAt: t0, ok: true, now: t0 + 0.3)
        // Answered, but within a second of the first: still a double-fire.
        do {
            let result = book.begin(key, entityId: "switch.a", value: .locked(true), echo: .state(["locked"]), now: t0 + 0.6)
            #expect(!result)
        }
        do {
            let result = book.begin(key, entityId: "switch.a", value: .locked(true), echo: .state(["locked"]), now: t0 + 1.2)
            #expect(result)
        }
        // Another control of the same entity is not throttled by it.
        do {
            let result = book.begin("switch.a#press", entityId: "switch.a", value: .pressed, echo: .none, now: t0 + 1.3)
            #expect(result)
        }
    }

    @Test func numbersReplaceAndStaleAnswersAreIgnored() {
        var book = KhalaPendingBook()
        let slider = "media_player.a#slider"
        _ = book.begin(slider, entityId: "media_player.a", value: .number(0.3),
                       echo: .attributeNumber("volume_level", 0.3, tolerance: 0.011), now: t0)
        do {
            let result = book.begin(slider, entityId: "media_player.a", value: .number(0.5),
                           echo: .attributeNumber("volume_level", 0.5, tolerance: 0.011), now: t0 + 0.1)
            #expect(result)
        }
        // The first call's failure doesn't wipe the newer value.
        book.answer(slider, startedAt: t0, ok: false, now: t0 + 0.2)
        #expect(book.pending(slider)?.value == .number(0.5))
        book.answer(slider, startedAt: t0 + 0.1, ok: true, now: t0 + 0.3)
        book.reconcile(entities: entity("on", "media_player.a"), attributes: ["media_player.a": ["volume_level": 0.5]],
                       now: t0 + 0.4)
        #expect(book.pending(slider) == nil)
    }

    @Test func pressEndsWithItsAnswer() {
        var book = KhalaPendingBook()
        _ = book.begin("button.a#press", entityId: "button.a", value: .pressed, echo: .none, now: t0)
        book.answer("button.a#press", startedAt: t0, ok: true, now: t0 + 0.2)
        #expect(book.pending("button.a#press") == nil)
    }

    @Test func echoes() {
        let cover = KhalaPendingEcho.power(domain: "cover", on: true)
        #expect(cover.isEchoed(by: KhalaScreenFixtures.entity("cover.a", "opening"), attributes: [:]))
        #expect(!cover.isEchoed(by: KhalaScreenFixtures.entity("cover.a", "closed"), attributes: [:]))
        let climate = KhalaPendingEcho.power(domain: "climate", on: true)
        #expect(climate.isEchoed(by: KhalaScreenFixtures.entity("climate.a", "heat_cool"), attributes: [:]))
        #expect(!climate.isEchoed(by: KhalaScreenFixtures.entity("climate.a", "off"), attributes: [:]))
        let number = KhalaPendingEcho.stateNumber(80, tolerance: 0.0001)
        #expect(number.isEchoed(by: KhalaScreenFixtures.entity("number.a", "80.0"), attributes: [:]))
        #expect(!KhalaPendingEcho.none.isEchoed(by: KhalaScreenFixtures.entity("button.a", "x"), attributes: [:]))
        #expect(KhalaPendingEcho.choice(.source, "TV")
            .isEchoed(by: KhalaScreenFixtures.entity("media_player.a", "on"), attributes: ["source": "TV"]))
    }
}
