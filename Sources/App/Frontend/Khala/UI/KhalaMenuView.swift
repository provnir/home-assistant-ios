import SFSafeSymbols
import SwiftUI

/// The main menu, revealed under the screen card (mockup `DayMenu`): who/where, a search field, the destinations,
/// the DEVICES list built from Home Assistant data, and Settings at the bottom. Search filters destinations and
/// devices by name; it never side-scrolls. Its ground is the shell's, drawn across the whole window.
struct KhalaMenuView: View {
    let homeName: String
    let summary: String
    let userName: String?
    let destination: KhalaDestination
    let cameraCount: Int
    let automationCount: Int
    let devices: [KhalaDevice]
    /// Whether the menu is revealed; closing it clears the search.
    let isOpen: Bool
    /// Bumped by the shell to put the cursor in the search field (Today's search button).
    let searchFocusRequest: Int
    let onSelect: (KhalaDestination) -> Void
    let onDevice: (KhalaDevice) -> Void
    let onEditDevices: () -> Void
    let onSettings: () -> Void

    @State private var search = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        let destinations = KhalaDestination.allCases.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
        }
        let shownDevices = devices.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(verbatim: String((userName ?? homeName).prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(KhalaTheme.groundFlat)
                    .frame(width: 40, height: 40)
                    .background(KhalaTheme.ink, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(homeName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(KhalaTheme.ink)
                        .lineLimit(1)
                    Text(summary)
                        .font(KhalaTheme.secondaryText)
                        .foregroundStyle(KhalaTheme.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 10)

            HStack(spacing: 8) {
                Image(systemSymbol: .magnifyingglass)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KhalaTheme.tertiary)
                TextField(KhalaText.search, text: $search)
                    .font(.system(size: 15))
                    .foregroundStyle(KhalaTheme.ink)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemSymbol: .xmark)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(KhalaTheme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.5))

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(destinations) { item in
                        KhalaMenuRow(
                            title: item.title,
                            symbol: KhalaTheme.symbol(item),
                            symbolColor: item == .cameras ? KhalaTheme.accent(.security) : KhalaTheme.ink,
                            trailing: trailing(for: item),
                            isSelected: item == destination
                        ) {
                            onSelect(item)
                        }
                    }

                    HStack {
                        Text(KhalaText.devices)
                            .font(KhalaTheme.caption)
                            .kerning(1)
                            .foregroundStyle(KhalaTheme.muted)
                        Spacer()
                        Button(KhalaText.editDevices, action: onEditDevices)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(KhalaTheme.secondary)
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                    if shownDevices.isEmpty {
                        Text(KhalaText.noDevices)
                            .font(KhalaTheme.secondaryText)
                            .foregroundStyle(KhalaTheme.muted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    ForEach(shownDevices) { device in
                        KhalaMenuRow(
                            title: device.name,
                            symbol: KhalaTheme.symbol(device.category),
                            symbolColor: KhalaTheme.accent(device.category),
                            chipTint: KhalaTheme.tint(device.category),
                            trailing: device.stateText
                        ) {
                            onDevice(device)
                        }
                    }
                }
                .padding(.top, 10)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)

            KhalaMenuRow(title: KhalaText.settings, symbol: .gearshape, symbolColor: KhalaTheme.ink, action: onSettings)
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: searchFocusRequest) { _ in
            isSearchFocused = true
        }
        .onChange(of: isOpen) { isOpen in
            guard !isOpen else { return }
            search = ""
            isSearchFocused = false
        }
    }

    private func trailing(for destination: KhalaDestination) -> String? {
        switch destination {
        case .cameras: return cameraCount > 0 ? "\(cameraCount)" : nil
        case .automations: return automationCount > 0 ? "\(automationCount)" : nil
        case .today, .dashboards: return nil
        }
    }
}

#Preview {
    KhalaMenuView(
        homeName: "Home",
        summary: KhalaText.allClear,
        userName: "Sam",
        destination: .today,
        cameraCount: 8,
        automationCount: 3,
        devices: [
            KhalaDevice(
                id: "a", name: "Rover", category: .car, primaryEntityId: "sensor.a",
                stateText: "72%", memberEntityIds: [], isPinned: false
            ),
            KhalaDevice(
                id: "b", name: "Hot water", category: .heat, primaryEntityId: "switch.b",
                stateText: "Off", memberEntityIds: [], isPinned: true
            ),
        ],
        isOpen: true,
        searchFocusRequest: 0,
        onSelect: { _ in },
        onDevice: { _ in },
        onEditDevices: {},
        onSettings: {}
    )
    .frame(width: 312)
    .background(KhalaGround(style: .menu))
}
