import AppKit
import Combine

/// State of the Settings and onboarding windows: reads SettingsStore, writes
/// every change back, and refreshes permission states while a window shows.
@MainActor
final class SettingsModel: ObservableObject {
    enum Destination: String, CaseIterable {
        case converted, beside, custom

        var title: String {
            switch self {
            case .converted: "Téléchargements › Convertis"
            case .beside: "À côté de l’original"
            case .custom: "Dossier personnalisé…"
            }
        }
    }

    private static let refreshInterval: TimeInterval = 1

    @Published var triggers = SettingsStore.triggers {
        didSet { SettingsStore.triggers = triggers }
    }
    @Published var hotKey = SettingsStore.hotKey {
        didSet { SettingsStore.hotKey = hotKey }
    }
    @Published var destination: Destination {
        didSet { applyDestination() }
    }
    @Published private(set) var customFolder = SettingsStore.customOutputFolder
    @Published var quality = SettingsStore.outputQuality {
        didSet { SettingsStore.outputQuality = quality }
    }
    @Published var stripsLocation = SettingsStore.stripsLocation {
        didSet { SettingsStore.stripsLocation = stripsLocation }
    }
    @Published var playsSound = SettingsStore.playsCompletionSound {
        didSet { SettingsStore.playsCompletionSound = playsSound }
    }
    @Published var launchAtLogin = LoginItem.isEnabled {
        didSet {
            guard launchAtLogin != LoginItem.isEnabled else { return }
            LoginItem.setEnabled(launchAtLogin)
            refreshPermissions()
        }
    }
    @Published private(set) var accessibilityGranted = PermissionsManager.isAccessibilityTrusted
    @Published private(set) var finderAutomation = PermissionsManager.finderAutomationStatus()
    @Published private(set) var loginNeedsApproval = LoginItem.needsApproval

    private var timer: Timer?

    init() {
        destination = switch SettingsStore.outputDestination {
        case .convertedFolder: .converted
        case .besideOriginal: .beside
        case .custom: .custom
        }
    }

    func setTrigger(_ key: TriggerKey, for mode: WheelMode) {
        triggers = triggers.assigning(key, to: mode)
    }

    /// Folder picker; falls back to the previous destination when cancelled.
    func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        NSApp.activate()
        guard panel.runModal() == .OK, let folder = panel.url else {
            if customFolder == nil { destination = .converted }
            return
        }
        customFolder = folder
        destination = .custom
    }

    private func applyDestination() {
        switch destination {
        case .converted:
            SettingsStore.outputDestination = .convertedFolder
        case .beside:
            SettingsStore.outputDestination = .besideOriginal
        case .custom:
            if let customFolder {
                SettingsStore.outputDestination = .custom(customFolder)
            } else {
                // Not from inside a SwiftUI update: the picker is modal.
                DispatchQueue.main.async { self.chooseCustomFolder() }
            }
        }
    }

    /// Live permission states (§5.7) while a window is open, never at rest.
    func startRefreshing() {
        refreshPermissions()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }

    func refreshPermissions() {
        accessibilityGranted = PermissionsManager.isAccessibilityTrusted
        finderAutomation = PermissionsManager.finderAutomationStatus()
        loginNeedsApproval = LoginItem.needsApproval
    }

    /// First request shows the macOS prompt; once refused, only Settings can change it.
    func requestFinderAutomation() {
        if finderAutomation == .denied {
            PermissionsManager.openAutomationSettings()
            return
        }
        Task {
            _ = await FinderSelection.current()
            refreshPermissions()
        }
    }
}
