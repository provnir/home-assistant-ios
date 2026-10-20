import SFSafeSymbols
import SwiftUI

/// A 76 pt tile of a controls grid (mockup `DayCar`): glyph over a short label, tinted in the screen's accent while
/// active (locked, on, open), white otherwise. Unlocking and opening ask first; a `select` offers its options as a
/// pull-down (a vertical list, never a side-scroller).
struct KhalaControlTile: View {
    let control: KhalaControl
    let category: KhalaCategory
    let onCall: (KhalaServiceCall) -> Void

    @State private var confirming = false

    var body: some View {
        Group {
            if !control.options.isEmpty {
                Menu {
                    ForEach(control.options, id: \.self) { option in
                        Button {
                            onCall(KhalaServiceCall(
                                domainOf(control.entityId),
                                "select_option",
                                entityId: control.entityId,
                                data: ["option": option]
                            ))
                        } label: {
                            if KhalaText.humanized(state: option) == control.stateText {
                                Label(KhalaText.humanized(state: option), systemSymbol: .checkmark)
                            } else {
                                Text(KhalaText.humanized(state: option))
                            }
                        }
                    }
                } label: {
                    face
                }
            } else {
                Button {
                    guard let plan = control.call else { return }
                    if control.needsConfirmation {
                        confirming = true
                    } else {
                        onCall(plan.call)
                    }
                } label: {
                    face
                }
                .buttonStyle(.plain)
                .disabled(control.call == nil)
            }
        }
        .confirmationDialog(
            KhalaScreenText.confirmAction(actionTitle),
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(actionTitle) {
                if let plan = control.call { onCall(plan.call) }
            }
            Button(KhalaScreenText.cancel, role: .cancel) {}
        }
    }

    private var face: some View {
        VStack(spacing: 6) {
            Image(systemSymbol: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(control.isActive ? KhalaTheme.accent(category) : KhalaTheme.ink)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(control.isActive ? KhalaTheme.accent(category) : KhalaTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(
            control.isActive ? KhalaTheme.tint(category) : KhalaTheme.card,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .modify { view in
            if control.isActive { view } else { view.khalaCardShadow() }
        }
        .opacity(control.call == nil && control.options.isEmpty ? 0.45 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(control.stateText)
    }

    /// Locks read as their state ("Locked"); the rest by name.
    private var label: String {
        if control.glyph == .lock || control.glyph == .unlock { return control.stateText }
        if !control.options.isEmpty { return "\(control.title)\n\(control.stateText)" }
        return control.title
    }

    private var actionTitle: String {
        guard let plan = control.call else { return control.title }
        switch plan.service {
        case "unlock": return "Unlock \(control.title.lowercased())"
        case "open_cover": return "Open \(control.title.lowercased())"
        default: return control.title
        }
    }

    private var symbol: SFSymbol {
        switch control.glyph {
        case .lock: return .lockFill
        case .unlock: return .lockOpenFill
        case .shield: return .shieldFill
        case .chargePort: return .boltFill
        case .frunk, .trunk: return .carRear
        case .window: return .arrowUpDoc
        case .lights: return .lightbulbFill
        case .horn: return .speakerWave2Fill
        case .power: return .power
        case .seat: return .flameFill
        case .wheel: return .dial
        case .defrost: return .sparkles
        case .fan: return .fanblades
        case .button: return .circleCircle
        case .generic: return .sliderHorizontal3
        }
    }

    private func domainOf(_ entityId: String) -> String {
        entityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? entityId
    }
}

#Preview {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
        KhalaControlTile(
            control: KhalaControl(
                entityId: "lock.rover", title: "Lock", stateText: "Locked", glyph: .lock, isActive: true,
                call: KhalaServiceCallPlan(domain: "lock", service: "unlock", entityId: "lock.rover"),
                options: [], needsConfirmation: true
            ),
            category: .car,
            onCall: { _ in }
        )
        KhalaControlTile(
            control: KhalaControl(
                entityId: "button.flash", title: "Flash lights", stateText: "", glyph: .lights, isActive: false,
                call: KhalaServiceCallPlan(domain: "button", service: "press", entityId: "button.flash"),
                options: [], needsConfirmation: false
            ),
            category: .car,
            onCall: { _ in }
        )
    }
    .padding()
    .background(KhalaGround())
}
