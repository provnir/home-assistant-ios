import Foundation
@testable import HomeAssistant
import Testing

struct KhalaDrawerSpringTests {
    @Test func startsWhereItIsAtTheGivenVelocity() {
        let spring = KhalaDrawerSpring(from: 100, target: 312, velocity: 900, duration: 0.38, bounce: 0)
        #expect(abs(spring.position(at: 0) - 100) < 1e-9)
        #expect(abs(spring.velocity(at: 0) - 900) < 1e-9)
        let bouncy = KhalaDrawerSpring(from: 100, target: 312, velocity: 900, duration: 0.38, bounce: 0.08)
        #expect(abs(bouncy.position(at: 0) - 100) < 1e-9)
        #expect(abs(bouncy.velocity(at: 0) - 900) < 1e-6)
    }

    @Test func velocityIsTheDerivative() {
        for bounce in [0.0, 0.08] {
            let spring = KhalaDrawerSpring(from: 250, target: 0, velocity: -700, duration: 0.38, bounce: bounce)
            for t in [0.02, 0.1, 0.25] {
                let h = 1e-6
                let numeric = (spring.position(at: t + h) - spring.position(at: t - h)) / (2 * h)
                #expect(abs(numeric - spring.velocity(at: t)) < 1e-3)
            }
        }
    }

    @Test func settlesWithinAboutItsDuration() {
        let spring = KhalaDrawerSpring(from: 0, target: 312, velocity: 0, duration: 0.38, bounce: 0)
        #expect(!spring.isSettled(at: 0.1))
        #expect(spring.isSettled(at: 0.8))
        #expect(abs(spring.position(at: 2) - 312) < 0.01)
    }

    @Test func criticallyDampedFromRestNeverOvershoots() {
        let spring = KhalaDrawerSpring(from: 312, target: 0, velocity: 0, duration: 0.38, bounce: 0)
        for step in 0 ... 100 {
            #expect(spring.position(at: Double(step) * 0.01) >= 0)
        }
    }

    @Test func aBounceOvershootsALittle() {
        let spring = KhalaDrawerSpring(from: 150, target: 312, velocity: 1200, duration: 0.38, bounce: 0.08)
        let peak = (0 ... 100).map { spring.position(at: Double($0) * 0.01) }.max() ?? 0
        #expect(peak > 312 && peak < 340)
    }
}
