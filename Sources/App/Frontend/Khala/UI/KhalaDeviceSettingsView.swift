import Shared
import SwiftUI

/// Where the user decides which entities Khala treats as devices and in what role: pinned devices come first in
/// the menu and on the Now card. Entities are chosen with the app's existing `EntityPicker`; nothing about any
/// particular home is assumed.
struct KhalaDeviceSettingsView: View {
    let serverId: String
    let entityNames: [String: String]
    let onSave: ([KhalaRoleAssignment]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var assignments: [KhalaRoleAssignment]
    @State private var picked: HAAppEntity?

    init(
        serverId: String,
        entityNames: [String: String],
        assignments: [KhalaRoleAssignment],
        onSave: @escaping ([KhalaRoleAssignment]) -> Void
    ) {
        self.serverId = serverId
        self.entityNames = entityNames
        self.onSave = onSave
        self._assignments = State(initialValue: assignments)
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach($assignments) { $assignment in
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entityNames[assignment.entityId] ?? assignment.entityId)
                                    .font(.body.weight(.semibold))
                                Text(assignment.entityId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            TextField(
                                KhalaText.label,
                                text: Binding(
                                    get: { assignment.label ?? "" },
                                    set: { assignment.label = $0 }
                                )
                            )
                            Picker(KhalaText.role, selection: $assignment.role) {
                                ForEach(KhalaCategory.assignableRoles, id: \.self) { role in
                                    Text(role.displayName).tag(role)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        assignments.remove(atOffsets: offsets)
                    }
                } header: {
                    Text(KhalaText.pinnedDevices)
                } footer: {
                    Text(KhalaText.pinnedDevicesFooter)
                }

                Section {
                    EntityPicker(selectedServerId: serverId, selectedEntity: $picked, domainFilter: nil)
                } header: {
                    Text(KhalaText.addDevice)
                } footer: {
                    Text(KhalaText.addDeviceFooter)
                }
            }
            .navigationTitle(KhalaText.devicesTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(KhalaText.done) {
                        onSave(assignments)
                        dismiss()
                    }
                }
            }
            .onChange(of: picked) { entity in
                guard let entity else { return }
                if !assignments.contains(where: { $0.entityId == entity.entityId }) {
                    assignments.append(KhalaRoleAssignment(
                        entityId: entity.entityId,
                        role: KhalaCategory.suggestedRole(forDomain: entity.domain),
                        label: nil
                    ))
                }
                picked = nil
            }
        }
        .navigationViewStyle(.stack)
    }
}

#Preview {
    KhalaDeviceSettingsView(
        serverId: "preview",
        entityNames: ["switch.relay_7": "Relay 7"],
        assignments: [KhalaRoleAssignment(entityId: "switch.relay_7", role: .heat, label: "Hot water")],
        onSave: { _ in }
    )
}
