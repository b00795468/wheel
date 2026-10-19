import AppKit
import Carbon.HIToolbox

/// System-wide shortcut through Carbon's RegisterEventHotKey, which needs
/// no permission at all (§5.3).
@MainActor
final class HotKeyCenter {
    /// "PVTK": identifies Pivot's hot key among the app's Carbon events.
    private static let signature: OSType = 0x5056_544B

    var onPress: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Returns false when another app already owns the shortcut.
    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        unregister()
        installHandlerIfNeeded()
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.carbonModifiers, identifier,
                                         GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            AppInfo.log.error("Shortcut \(combo.display, privacy: .public) unavailable (\(status))")
        }
        return status == noErr
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        hotKey = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let center = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated { center.onPress?() }
            return noErr
        }, 1, &spec, center, &handler)
    }
}
