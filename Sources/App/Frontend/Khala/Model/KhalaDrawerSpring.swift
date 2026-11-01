import Foundation

/// A damped spring toward `target`, parameterised like SwiftUI's `.spring(duration:bounce:)` (response =
/// `duration`, damping ratio = `1 − bounce`), solved in closed form so any instant can be read exactly: the drawer
/// samples it once per display frame, and an interruption reads the very position on screen.
struct KhalaDrawerSpring: Equatable {
    let from: Double
    let target: Double
    /// Points per second at `t = 0` (the finger's release velocity, or the velocity of the spring it replaces).
    let velocity: Double
    let duration: Double
    let bounce: Double

    private var omega: Double { 2 * Double.pi / max(duration, 0.01) }
    private var damping: Double { 1 - min(max(bounce, 0), 0.99) }

    func position(at time: Double) -> Double {
        target + displacement(at: max(0, time)).position
    }

    func velocity(at time: Double) -> Double {
        displacement(at: max(0, time)).velocity
    }

    /// Close enough to rest to snap: within half a point and slower than 10 pt/s.
    func isSettled(at time: Double) -> Bool {
        let state = displacement(at: max(0, time))
        return abs(state.position) < 0.5 && abs(state.velocity) < 10
    }

    private func displacement(at t: Double) -> (position: Double, velocity: Double) {
        let x0 = from - target
        let v0 = velocity
        let w = omega
        let zeta = damping
        if zeta >= 1 {
            // Critically damped.
            let decay = exp(-w * t)
            let b = v0 + w * x0
            return ((x0 + b * t) * decay, (v0 - w * t * b) * decay)
        }
        let wd = w * (1 - zeta * zeta).squareRoot()
        let a = x0
        let b = (v0 + zeta * w * x0) / wd
        let decay = exp(-zeta * w * t)
        let cosine = cos(wd * t)
        let sine = sin(wd * t)
        let position = decay * (a * cosine + b * sine)
        let speed = decay * ((b * wd - zeta * w * a) * cosine - (a * wd + zeta * w * b) * sine)
        return (position, speed)
    }
}
