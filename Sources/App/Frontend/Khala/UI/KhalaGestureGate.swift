import UIKit

/// A gesture delegate that only answers whether a recognizer may begin (kept apart from the view, whose own
/// `gestureRecognizerShouldBegin(_:)` has the same selector).
final class KhalaGestureGate: NSObject, UIGestureRecognizerDelegate {
    var shouldBegin: ((UIGestureRecognizer) -> Bool)?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        shouldBegin?(gestureRecognizer) ?? false
    }
}
