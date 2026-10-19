import AppKit
import SwiftUI

/// Placeholder Settings window (phase 1). Real settings arrive in phase 6.
struct SettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text(AppInfo.name)
                .font(.title2.weight(.semibold))
            Text("L'application fonctionne en arrière-plan.")
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Text("Version \(AppInfo.version)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quitter \(AppInfo.name)") { NSApp.terminate(nil) }
            }
        }
        .padding(24)
        .frame(width: 420, height: 260)
    }
}
