import SwiftUI

/// One permission with its live state and a button to grant it (§5.7).
struct PermissionRow: View {
    let title: String
    let detail: String
    let status: PermissionsManager.Status
    let action: @MainActor () -> Void
    /// The required permission while missing: accent button, default action.
    var prominent = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: status == .granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if status == .granted {
                Text("Autorisé").foregroundStyle(.secondary)
            } else {
                if prominent {
                    Button("Autoriser…", action: action)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accentColor)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Autoriser…", action: action)
                }
            }
        }
    }
}
