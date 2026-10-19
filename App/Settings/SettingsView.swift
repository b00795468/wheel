import AppKit
import SwiftUI

/// The Settings window (§5.7), reached by opening the app again.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Autorisations") {
                    PermissionRow(title: "Accessibilité", detail: "Indispensable\u{202F}: détecte le geste.",
                                  status: model.accessibilityGranted ? .granted : .denied,
                                  action: PermissionsManager.grantAccessibility)
                    PermissionRow(title: "Contrôle du Finder", detail: "Facultatif\u{202F}: pour le raccourci clavier.",
                                  status: model.finderAutomation, action: model.requestFinderAutomation)
                }
                Section("Roues") {
                    ForEach(WheelMode.allCases, id: \.self) { mode in
                        Picker(mode.title, selection: Binding(
                            get: { model.triggers.key(for: mode) },
                            set: { model.setTrigger($0, for: mode) }
                        )) {
                            ForEach(TriggerKey.allCases, id: \.self) { Text($0.name).tag($0) }
                        }
                    }
                }
                Section("Mode clavier") {
                    LabeledContent("Raccourci") {
                        ShortcutRecorder(combo: $model.hotKey).fixedSize()
                    }
                    Text("Ouvre la roue sur les fichiers sélectionnés dans le Finder\u{202F}: flèches pour choisir, Entrée pour appliquer, Échap pour annuler.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Sortie") {
                    Picker("Dossier", selection: $model.destination) {
                        ForEach(SettingsModel.Destination.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if model.destination == .custom, let folder = model.customFolder {
                        LabeledContent("Emplacement") {
                            HStack {
                                Text(folder.path).lineLimit(1).truncationMode(.middle)
                                Button("Changer…") { model.chooseCustomFolder() }
                            }
                        }
                    }
                    Picker("Qualité par défaut", selection: $model.quality) {
                        ForEach(OutputQuality.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Retirer les données de localisation", isOn: $model.stripsLocation)
                    Toggle("Son à la fin d’une conversion", isOn: $model.playsSound)
                }
                Section("Général") {
                    Toggle("Ouvrir au démarrage", isOn: $model.launchAtLogin)
                    if model.loginNeedsApproval {
                        Text("À approuver dans Réglages Système › Général › Ouverture.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Text("\(AppInfo.name) \(AppInfo.version)").foregroundStyle(.secondary)
                Spacer()
                Button("Quitter \(AppInfo.name)") { NSApp.terminate(nil) }
            }
            .padding(16)
        }
        .frame(width: 520, height: 660)
        .onAppear { model.startRefreshing() }
        .onDisappear { model.stopRefreshing() }
    }
}
