import Foundation

/// A `number.*` (or climate target) a screen adjusts with − / + : value, bounds and step.
struct KhalaNumberSetting: Equatable {
    let entityId: String
    let title: String
    let value: Double
    let minimum: Double
    let maximum: Double
    let step: Double
    let unit: String?

    init?(_ entity: KhalaEntity, attributes: [String: Any]) {
        guard let value = Double(entity.state) else { return nil }
        self.entityId = entity.entityId
        self.title = entity.nameWithoutDevice
        self.value = value
        self.minimum = KhalaValue.double(attributes["min"]) ?? 0
        self.maximum = KhalaValue.double(attributes["max"]) ?? 100
        self.step = max(KhalaValue.double(attributes["step"]) ?? 1, 0.0001)
        self.unit = entity.unit
    }

    init(entityId: String, title: String, value: Double, minimum: Double, maximum: Double, step: Double, unit: String?) {
        self.entityId = entityId
        self.title = title
        self.value = value
        self.minimum = minimum
        self.maximum = maximum
        self.step = max(step, 0.0001)
        self.unit = unit
    }

    /// `value` moved by `steps` steps, kept in bounds and on the step grid.
    func stepped(_ steps: Int) -> Double {
        let raw = value + Double(steps) * step
        let snapped = (raw / step).rounded() * step
        return min(maximum, max(minimum, snapped))
    }

    /// Where `value` sits between the bounds, 0...1.
    var fraction: Double {
        guard maximum > minimum else { return 0 }
        return min(1, max(0, (value - minimum) / (maximum - minimum)))
    }

    var text: String { KhalaText.measurement(value, unit: unit) }

    func call(value newValue: Double) -> KhalaServiceCall {
        KhalaServiceCall("number", "set_value", entityId: entityId, data: ["value": newValue])
    }
}
