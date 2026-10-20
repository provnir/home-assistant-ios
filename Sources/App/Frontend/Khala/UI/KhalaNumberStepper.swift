import SFSafeSymbols
import SwiftUI

/// − value + for a `KhalaNumberSetting` (charge limit, charge current, climate target). Taps move a local value at
/// once and send it after a short pause, so five quick taps are one call; the value from Home Assistant takes
/// over again when it arrives.
struct KhalaNumberStepper: View {
    let setting: KhalaNumberSetting
    let category: KhalaCategory
    var large = false
    let onSet: (Double) -> Void

    @State private var pending: Double? = nil
    @State private var sendTask: Task<Void, Never>? = nil

    var body: some View {
        let shown = pending ?? setting.value
        HStack(spacing: 12) {
            if !large {
                Text(setting.title)
                    .font(KhalaTheme.body)
                    .foregroundStyle(KhalaTheme.secondary)
                Spacer(minLength: 8)
            }
            roundButton(.minus, enabled: shown > setting.minimum) { step(-1) }
            Text(KhalaText.measurement(shown, unit: setting.unit))
                .font(large ? .system(size: 44, weight: .semibold) : .system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(KhalaTheme.ink)
                .frame(minWidth: large ? 120 : 64)
                .accessibilityLabel(setting.title)
            roundButton(.plus, enabled: shown < setting.maximum) { step(1) }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: setting.value) { _ in
            pending = nil
        }
        .onDisappear { sendTask?.cancel() }
    }

    private func roundButton(_ symbol: SFSymbol, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemSymbol: symbol)
                .font(.system(size: large ? 20 : 15, weight: .semibold))
                .foregroundStyle(KhalaTheme.ink)
                .frame(width: large ? 52 : 40, height: large ? 52 : 40)
                .background(KhalaTheme.groundFlat, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func step(_ direction: Int) {
        let base = KhalaNumberSetting(
            entityId: setting.entityId,
            title: setting.title,
            value: pending ?? setting.value,
            minimum: setting.minimum,
            maximum: setting.maximum,
            step: setting.step,
            unit: setting.unit
        )
        let next = base.stepped(direction)
        pending = next
        sendTask?.cancel()
        sendTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            onSet(next)
        }
    }
}

#Preview {
    VStack {
        KhalaNumberStepper(
            setting: KhalaNumberSetting(entityId: "number.a", title: "Charge limit", value: 80, minimum: 50,
                                        maximum: 100, step: 1, unit: "%"),
            category: .car,
            onSet: { _ in }
        )
        KhalaNumberStepper(
            setting: KhalaNumberSetting(entityId: "climate.a", title: "Target", value: 21, minimum: 15,
                                        maximum: 28, step: 0.5, unit: "°"),
            category: .car,
            large: true,
            onSet: { _ in }
        )
    }
    .padding()
}
