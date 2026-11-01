import Foundation
@testable import HomeAssistant
import Testing

/// `KhalaValue` reads loosely typed attribute values the same way on every platform.
struct KhalaValueTests {
    @Test func numbers() {
        #expect(KhalaValue.double(3) == 3)
        #expect(KhalaValue.double(2.5) == 2.5)
        #expect(KhalaValue.double(NSNumber(value: 7.25)) == 7.25)
        #expect(KhalaValue.double(" 4.5 ") == 4.5)
        #expect(KhalaValue.double("abc") == nil)
        #expect(KhalaValue.double(nil) == nil)
        #expect(KhalaValue.double([1]) == nil)
        #expect(KhalaValue.int(2.9) == 2)
        #expect(KhalaValue.int("7.9") == 7)
        #expect(KhalaValue.int(-1.5) == -1)
        #expect(KhalaValue.int("x") == nil)
    }

    @Test func numbersFromJSON() throws {
        let json = try JSONSerialization.jsonObject(with: Data(#"{"i": 255, "d": 0.455, "s": "12"}"#.utf8))
        let object = try #require(json as? [String: Any])
        #expect(KhalaValue.int(object["i"]) == 255)
        #expect(KhalaValue.double(object["d"]) == 0.455)
        #expect(KhalaValue.int(object["s"]) == 12)
    }

    @Test func booleans() {
        #expect(KhalaValue.bool(true) == true)
        #expect(KhalaValue.bool(false) == false)
        #expect(KhalaValue.bool(NSNumber(value: true)) == true)
        #expect(KhalaValue.bool(NSNumber(value: 0)) == false)
        for word in ["true", "ON", "Yes"] { #expect(KhalaValue.bool(word) == true) }
        for word in ["false", "off", "NO"] { #expect(KhalaValue.bool(word) == false) }
        #expect(KhalaValue.bool("maybe") == nil)
        #expect(KhalaValue.bool(nil) == nil)
    }

    @Test func strings() {
        #expect(KhalaValue.string("on") == "on")
        #expect(KhalaValue.string("") == nil)
        #expect(KhalaValue.string(5) == nil)
        #expect(KhalaValue.string(NSNull()) == nil)
    }

    @Test func oneOrAList() {
        #expect(KhalaValue.list(nil).isEmpty)
        #expect(KhalaValue.list("07:00").count == 1)
        #expect(KhalaValue.list(["a", "b"]).count == 2)
        #expect(KhalaValue.list([String]()).isEmpty)
        let dictionaries = KhalaValue.dictionaries([["a": 1], "b", ["c": 2]])
        #expect(dictionaries.count == 2)
        #expect(KhalaValue.dictionaries(["a": 1]).count == 1)
        #expect(KhalaValue.dictionaries(nil).isEmpty)
    }
}
