import SwiftUI

/// First launch (§5.7): the gesture, the permissions, then where files go.
struct OnboardingView: View {
    private static let pageCount = 3

    @ObservedObject var model: SettingsModel
    @State var page = 0
    /// Not private: a private property would make the memberwise init private.
    @State var launchAtLogin = true
    /// Called with the "Ouvrir au démarrage" choice.
    let onFinish: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: gesturePage
                case 1: permissionsPage
                default: outputPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)
            .padding(.top, 28)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<Self.pageCount, id: \.self) { index in
                        Circle()
                            .fill(index == page ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                Spacer()
                if page > 0 {
                    Button("Retour") { page -= 1 }
                }
                if page < Self.pageCount - 1 {
                    Button("Continuer") { page += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Terminer") { onFinish(launchAtLogin) }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 470)
        .onAppear { model.startRefreshing() }
        .onDisappear { model.stopRefreshing() }
    }

    private var gesturePage: some View {
        VStack(spacing: 16) {
            GestureAnimationView()
            Text("Glisser, taper, déposer").font(.title2.weight(.semibold))
            Text("Commencez à glisser un fichier, tapez une touche\u{202F}: la roue s’ouvre autour du curseur. Lâchez le fichier sur une action.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 18) {
                ForEach(WheelMode.allCases, id: \.self) { mode in
                    HStack(spacing: 6) {
                        Text(model.triggers.key(for: mode).glyph).font(.headline)
                        Text(mode.title)
                    }
                }
            }
        }
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Autorisations").font(.title2.weight(.semibold))
            Text("macOS demande votre accord pour que \(AppInfo.name) voie le geste. L’état se met à jour tout seul.")
                .foregroundStyle(.secondary)
            PermissionRow(title: "Accessibilité", detail: "Indispensable\u{202F}: détecte la touche tapée pendant le glisser.",
                          status: model.accessibilityGranted ? .granted : .denied,
                          action: PermissionsManager.grantAccessibility)
            PermissionRow(title: "Contrôle du Finder", detail: "Facultatif\u{202F}: pour ouvrir la roue au clavier (\(model.hotKey.display)).",
                          status: model.finderAutomation, action: model.requestFinderAutomation)
            if !model.accessibilityGranted {
                Text("Sans l’Accessibilité, la roue ne peut pas s’ouvrir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var outputPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Où ranger les fichiers\u{202F}?").font(.title2.weight(.semibold))
            Text("Les originaux ne sont jamais modifiés\u{202F}: chaque résultat est un nouveau fichier.")
                .foregroundStyle(.secondary)
            Picker("Dossier", selection: $model.destination) {
                ForEach(SettingsModel.Destination.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if model.destination == .custom, let folder = model.customFolder {
                Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Toggle("Ouvrir \(AppInfo.name) au démarrage", isOn: $launchAtLogin)
            Text("Pour retrouver les réglages plus tard, ouvrez \(AppInfo.name) à nouveau (Spotlight ou dossier Applications).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
