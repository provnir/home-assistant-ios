// A stand-in for the one piece of HAKit that the upstream `Sources/Shared/Domain` capability parsers touch, so
// `linux-check.sh` can compile those files unchanged on Linux (HAKit itself needs Apple platforms). Only the shape
// their `init(entity:)` reads is here: `state` and `attributes.dictionary`. Never used by the app.
import Foundation

public struct HAEntity {
    public struct Attributes {
        public var dictionary: [String: Any]

        public init(dictionary: [String: Any]) {
            self.dictionary = dictionary
        }
    }

    public var entityId: String
    public var state: String
    public var attributes: Attributes

    public init(entityId: String, state: String, attributes: [String: Any]) {
        self.entityId = entityId
        self.state = state
        self.attributes = Attributes(dictionary: attributes)
    }
}
