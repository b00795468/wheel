import ServiceManagement

/// "Ouvrir au démarrage" through SMAppService (§5.7).
enum LoginItem {
    static var isEnabled: Bool {
        [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
    }

    /// macOS may want the user to approve it in System Settings › Login Items.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppInfo.log.error("Login item change to \(enabled, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
