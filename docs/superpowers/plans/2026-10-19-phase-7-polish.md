# Phase 7 — Finitions (critique Impeccable 24/40 → polish) — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Ce projet impose `superpowers:executing-plans` (voir CLAUDE.md, section Skills). Skills de design autorisés en phase 7 : Impeccable (critique faite, polish ici).

**Goal :** corriger les 5 problèmes prioritaires et les observations mineures de la critique `.impeccable/critique/2026-10-19T20-46-44Z__app.md`, dans l'ordre choisi par Raphaël (fin du parcours d'abord, tout le périmètre, terracotta plus profond sous le texte blanc).

**Architecture :** affinage, pas refonte : le monde visuel de la roue est conservé. Un `Announcer` partagé parle à VoiceOver (roue et pastille ne sont pas focalisables). La pastille gagne sa propre barre d'accent, du mouvement, deux lignes et le survol. Les opérations fournissent leur texte de progression. Les icônes suivent une règle (une seule icône d'image ; libellés seuls pour les préréglages). Typographie française (espaces insécables, apostrophes typographiques).

**Tech stack :** Swift 5, AppKit (NSAccessibility, NSTrackingArea, NSAnimationContext, CATransition), SwiftUI, XCTest.

**Spec :** `SPEC.md` §5.2, §5.6, §5.7, §6, §7 ; critique archivée (P1 ×3, P2 ×2, mineures).

## Contraintes globales

- Sobre, minimal, aucune fioriture ; clair et sombre parfaits ; respecter « Réduire les animations » (§5.2, §6).
- **Une seule couleur d'accent**, terracotta #D9663F (progression, onboarding) ; décision de Raphaël : un ton plus profond de la même teinte, #B8532F, derrière le libellé blanc du segment survolé (contraste ≥ 4,5:1).
- Pastille : près du coin bas-droit, « photo.png créé », clic → Finder, 3 s ; tâches > 1 s : progression + annulation (§5.6).
- Onboarding ≤ 3 écrans (§5.7).
- Interface en français ; code et commentaires en anglais ; zéro package externe.
- Preserve : comportement, gestes, réglages et textes factuels hors périmètre.

---

### Task 1 : la fin du parcours — pastille HUD

**Files :** Create `App/Feedback/Announcer.swift` · Replace `App/Feedback/HUDToast.swift` · Modify `App/Operations/FileOperation.swift`, `App/Operations/Tools/CompressOperation.swift`, `App/Operations/Tools/ResizeOperation.swift`, `App/Output/JobQueue.swift`, `App/AppDelegate.swift` (rendu debug) · Test `Tests/OperationTests/ActionTests.swift`

**Interfaces :** Produces `Announcer.say(_:)` ; `FileOperation.progressTitle` (défaut : « Conversion en PNG » pour `.convert`, le titre sinon ; « Compression » ; « Redimensionnement à 1920 px ») ; `HUDController.inform` affiché 4 s ; `HUDToast.isHovered`, `appear()`, `disappear()` ; debug `-debugHUDSnapshot <png> -debugHUDState progress|success|failure|notice`.

- [ ] **Step 1 : test** — dans `ActionTests` :

```swift
    func testProgressTitlesNameTheWork() {
        XCTAssertEqual(ConvertToImageOperation(format: .png, acceptsPDF: true).progressTitle, "Conversion en PNG")
        XCTAssertEqual(CompressOperation().progressTitle, "Compression")
        XCTAssertEqual(ResizeOperation(preset: .long1920).progressTitle, "Redimensionnement à \(ResizePreset.long1920.title)")
        XCTAssertEqual(CopyPathAction().progressTitle, "Copier le chemin")
    }
```

- [ ] **Step 2 : échec attendu** (`progressTitle` inconnu).
- [ ] **Step 3 : implémenter.**

`App/Feedback/Announcer.swift` :

```swift
import AppKit

/// Spoken feedback for VoiceOver: the wheel and the pills never take focus,
/// so what happens on them is announced instead (§7, accessibility).
@MainActor
enum Announcer {
    static func say(_ message: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}
```

`FileOperation` : requirement `/// Pill text while the job runs, e.g. "Conversion en PNG".` `var progressTitle: String { get }` ; extension :

```swift
    var progressTitle: String {
        switch kind {
        case .convert: "Conversion en \(title)"
        case .tools, .actions: title
        }
    }
```

`CompressOperation` : `var progressTitle: String { "Compression" }` ; `ResizeOperation` : `var progressTitle: String { "Redimensionnement à \(preset.title)" }` ; `JobQueue.run` : `hud.begin(title: operation.progressTitle, …)`.

`App/Feedback/HUDToast.swift` (remplacement complet) :

```swift
import AppKit

/// Pills stacked at the bottom-right of the screen reporting jobs (§5.6):
/// progress with a cancel button once a job runs over a second, then
/// "x créé" (click to reveal in Finder) or a human error message. Each
/// outcome is also spoken to VoiceOver, and a pill under the pointer stays.
@MainActor
final class HUDController {
    static let progressDelay: TimeInterval = 1
    static let successDuration: TimeInterval = 3
    static let noticeDuration: TimeInterval = 4
    static let failureDuration: TimeInterval = 5
    /// While the pointer rests on a pill, its removal waits this long again.
    private static let hoverGrace: TimeInterval = 1
    private static let margin: CGFloat = 16
    private static let spacing: CGFloat = 8

    private var visible: [HUDToast] = []

    func begin(title: String, symbol: String, onCancel: @escaping () -> Void) -> HUDToast {
        let toast = HUDToast(onCancel: onCancel)
        toast.showProgress(title: title, symbol: symbol)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.progressDelay) { [weak self] in
            guard let self, toast.isRunning else { return }
            self.present(toast)
        }
        return toast
    }

    func succeed(_ toast: HUDToast, message: String, outputs: [URL], symbol: String) {
        toast.showSuccess(message: message, outputs: outputs, symbol: symbol)
        present(toast)
        Announcer.say(message)
        remove(toast, after: Self.successDuration)
    }

    func fail(_ toast: HUDToast, message: String) {
        toast.showFailure(message: message)
        present(toast)
        Announcer.say(message)
        remove(toast, after: Self.failureDuration)
    }

    func cancel(_ toast: HUDToast) {
        remove(toast, after: 0)
    }

    /// A short notice that is not about a job (keyboard mode, onboarding).
    func inform(_ message: String, symbol: String) {
        let toast = HUDToast(onCancel: {})
        toast.showSuccess(message: message, outputs: [], symbol: symbol)
        present(toast)
        Announcer.say(message)
        remove(toast, after: Self.noticeDuration)
    }

    private func present(_ toast: HUDToast) {
        let isNew = !visible.contains { $0 === toast }
        if isNew { visible.append(toast) }
        layout()
        if isNew { toast.appear() }
    }

    private func remove(_ toast: HUDToast, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.visible.contains(where: { $0 === toast }) else { return }
            if delay > 0, toast.isHovered {
                self.remove(toast, after: Self.hoverGrace)
                return
            }
            self.visible.removeAll { $0 === toast }
            toast.disappear()
            self.layout()
        }
    }

    /// Stacks the pills upwards from the bottom-right corner of the screen under the cursor.
    private func layout() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            return
        }
        let frame = screen.visibleFrame
        var y = frame.minY + Self.margin
        for toast in visible {
            toast.panel.setFrameOrigin(CGPoint(x: frame.maxX - HUDToast.size.width - Self.margin, y: y))
            y += HUDToast.size.height + Self.spacing
        }
    }
}

/// One pill: a non-activating panel, so it never steals focus.
@MainActor
final class HUDToast {
    static let size = NSSize(width: 320, height: 64)
    /// Entrance: a short rise with a fade; Reduce Motion keeps the fade only.
    private static let appearDuration: TimeInterval = 0.18
    private static let disappearDuration: TimeInterval = 0.12
    private static let rise: CGFloat = 8

    let panel: NSPanel
    private let content: HUDToastView
    private let onCancel: () -> Void
    private var outputs: [URL] = []
    private(set) var isRunning = true

    var isHovered: Bool { content.isHovered }

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        content = HUDToastView(frame: NSRect(origin: .zero, size: Self.size))
        panel.contentView = content
        content.onClick = { [weak self] in self?.reveal() }
        content.onCancel = { [weak self] in self?.cancelTapped() }
    }

    func showProgress(title: String, symbol: String) {
        content.configure(icon: NSImage(systemSymbolName: symbol, accessibilityDescription: nil), tint: .labelColor,
                          text: "\(title)…", progress: 0, clickable: false)
    }

    func setProgress(_ fraction: Double) {
        guard isRunning else { return }
        content.setProgress(fraction)
    }

    func showSuccess(message: String, outputs: [URL], symbol: String) {
        isRunning = false
        self.outputs = outputs
        let icon = outputs.first.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        content.configure(icon: icon, tint: outputs.isEmpty ? .labelColor : nil, text: message, progress: nil,
                          clickable: !outputs.isEmpty)
    }

    /// The triangle carries the meaning; the colour stays neutral (one accent only, §6).
    func showFailure(message: String) {
        isRunning = false
        content.configure(icon: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil),
                          tint: .labelColor, text: message, progress: nil, clickable: false)
    }

    func appear() {
        let target = panel.frame.origin
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        if !reduceMotion {
            panel.setFrameOrigin(CGPoint(x: target.x, y: target.y - Self.rise))
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.appearDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrameOrigin(target)
            }
        }
    }

    func disappear() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.disappearDuration
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { self.panel.orderOut(nil) }
        }
    }

    private func reveal() {
        guard !outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
    }

    private func cancelTapped() {
        guard isRunning else { return }
        isRunning = false
        onCancel()
    }
}

@MainActor
private final class HUDToastView: NSView {
    private static let leading: CGFloat = 56
    private static let iconSide: CGFloat = 32
    private static let cancelSide: CGFloat = 24

    var onClick: (() -> Void)?
    var onCancel: (() -> Void)?
    private(set) var isHovered = false
    private var isClickable = false

    private let material = NSVisualEffectView()
    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private let bar = ProgressCapsule()
    private let cancelButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        material.frame = bounds
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 14
        material.layer?.masksToBounds = true
        addSubview(material)

        icon.frame = NSRect(x: 14, y: (bounds.height - Self.iconSide) / 2, width: Self.iconSide, height: Self.iconSide)
        icon.setAccessibilityElement(false)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byWordWrapping
        label.cell?.truncatesLastVisibleLine = true
        label.setAccessibilityElement(false)
        cancelButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Annuler")
        cancelButton.toolTip = "Annuler"
        cancelButton.isBordered = false
        cancelButton.contentTintColor = .secondaryLabelColor
        cancelButton.frame = NSRect(x: bounds.width - 36, y: (bounds.height - Self.cancelSide) / 2,
                                    width: Self.cancelSide, height: Self.cancelSide)
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        [icon, label, bar, cancelButton].forEach(addSubview)
        setAccessibilityElement(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `progress` nil hides the bar and the cancel button and lets the text use two lines.
    func configure(icon image: NSImage?, tint: NSColor?, text: String, progress: Double?, clickable: Bool) {
        icon.image = image
        icon.contentTintColor = tint
        label.stringValue = text
        isClickable = clickable
        let running = progress != nil
        bar.isHidden = !running
        cancelButton.isHidden = !running
        bar.fraction = progress ?? 0
        let width = bounds.width - Self.leading - (running ? 48 : 16)
        if running {
            label.maximumNumberOfLines = 1
            label.frame = NSRect(x: Self.leading, y: 30, width: width, height: 16)
            bar.frame = NSRect(x: Self.leading, y: 20, width: width, height: 4)
        } else {
            label.maximumNumberOfLines = 2
            let height = min(ceil(label.sizeThatFits(NSSize(width: width, height: 40)).height), 32)
            label.frame = NSRect(x: Self.leading, y: (bounds.height - height) / 2, width: width, height: height)
        }
        setAccessibilityLabel(text)
        setAccessibilityRole(clickable ? .button : .staticText)
        setAccessibilityHelp(clickable ? "Afficher dans le Finder" : nil)
    }

    func setProgress(_ fraction: Double) {
        bar.fraction = fraction
    }

    // The panel belongs to an inactive app: cursor rects do not apply, a
    // tracking area with cursor updates does.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func cursorUpdate(with event: NSEvent) {
        (isClickable ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isClickable { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isClickable else { return false }
        onClick?()
        return true
    }

    @objc private func cancelPressed() {
        onCancel?()
    }
}

/// Thin progress bar in the accent colour (§6: the accent marks progress).
@MainActor
private final class ProgressCapsule: NSView {
    var fraction: Double = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let width = bounds.width * min(max(fraction, 0), 1)
        guard width > 0 else { return }
        Theme.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: max(width, bounds.height), height: bounds.height),
                     xRadius: radius, yRadius: radius).fill()
    }
}

#if DEBUG
extension HUDToast {
    /// Offscreen render of one pill state, to check its layout without capture rights.
    static func debugSnapshot(state: String, to path: String) {
        let toast = HUDToast(onCancel: {})
        switch state {
        case "progress":
            toast.showProgress(title: "Conversion en PNG", symbol: "photo")
            toast.setProgress(0.42)
        case "failure":
            toast.showFailure(message: "Le moteur audio et vidéo est introuvable. Réinstallez l’application.")
        case "notice":
            toast.showSuccess(message: "Pivot est prêt\u{202F}: glissez un fichier, puis appuyez brièvement sur ⇧\u{00A0}Maj.",
                              outputs: [], symbol: "checkmark.circle")
        default:
            toast.showSuccess(message: "Vacances à la plage, été 2026.png créé", outputs: [URL(fileURLWithPath: "/etc/hosts")],
                              symbol: "photo")
        }
        let view = toast.content
        view.appearance = NSApp.effectiveAppearance
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
```

(`content` est `private` : dans le bloc DEBUG, passer `content` en `fileprivate(set)` n'est pas nécessaire puisque l'extension est dans le même fichier — `private` sur un membre de type est visible des extensions du même fichier.)

`AppDelegate`, bloc DEBUG : `if let path = UserDefaults.standard.string(forKey: "debugHUDSnapshot") { HUDToast.debugSnapshot(state: UserDefaults.standard.string(forKey: "debugHUDState") ?? "success", to: path) }`.

- [ ] **Step 4 : tests + build ; rendus des 4 états en clair et sombre.**
- [ ] **Step 5 : commit** `Phase 7: finished HUD pill (accent progress, motion, hover, VoiceOver)`.

---

### Task 2 : la roue — accessibilité, contraste, détails

**Files :** Modify `App/Theme.swift`, `App/Wheel/WheelModel.swift`, `App/Wheel/WheelView.swift`, `App/Wheel/WheelController.swift` · Test `Tests/GestureTests/WheelModelTests.swift`

**Interfaces :** `Theme.accentStrong`, `Theme.swapDuration` ; `WheelItem.title` ; `WheelModel.title` = « Outils › Redimensionner » en sous-roue ; slot sans icône quand `symbol` est vide.

- [ ] **Step 1 : tests** — `testOpeningAGroupShowsItsChildrenAndBack` attend `"Outils › Redimensionner"` après `open` ; ajouter :

```swift
    func testItemTitles() {
        XCTAssertEqual(WheelItem.segment(WheelSegment(id: "a", title: "PNG", symbol: "photo")).title, "PNG")
        XCTAssertEqual(WheelItem.more.title, "Plus…")
        XCTAssertEqual(WheelItem.back.title, "Retour")
    }
```

- [ ] **Step 2 : échec attendu.**
- [ ] **Step 3 : implémenter.**
  - `Theme` : commentaire de tête `/// Visual constants shared by the wheel, the HUD and the onboarding.` ; `accent` : `/// The single warm accent (§6), terracotta: progress, onboarding.` ; ajouter

```swift
    /// Same hue one step deeper, behind the hovered segment's white label:
    /// about 4.9:1 where the lighter tone gives 3.55:1 (WCAG AA for 11 pt text).
    static let accentStrong = NSColor(srgbRed: 0xB8 / 255, green: 0x53 / 255, blue: 0x2F / 255, alpha: 1)
    /// Crossfade when a wheel's items change (mode switch, page, sub-wheel).
    static let swapDuration: TimeInterval = 0.1
```

  - `WheelModel.swift` : `var title: String { parent.map { "\(mode.title) › \($0.title)" } ?? mode.title }` ; dans `WheelItem` :

```swift
    var title: String {
        switch self {
        case .segment(let segment): segment.title
        case .more: Self.moreTitle
        case .back: Self.backTitle
        }
    }
```

  - `WheelView` :
    - `highlightedSlot.didSet` : en plus de `setHighlighted`, `view.drawsSeparator = !(highlighted == index || highlighted.map { ($0 + 1) % slotViews.count } == index)` (le filet ne longe plus le segment survolé) ;
    - `setItems` : avant de retirer les anciens slots, si `!slotViews.isEmpty` et pas « Réduire les animations », `let fade = CATransition(); fade.type = .fade; fade.duration = Theme.swapDuration; layer?.add(fade, forKey: "swap")` ;
    - `emptyLabel` : cadre 200 × 52 centré sur le milieu de l'anneau (`y: center.y + ringMiddle - 26`) ;
    - `WheelSlotView` : `var drawsSeparator = true { didSet { needsDisplay = true } }` et `guard drawsSeparator, geometry.slotCount > 1` ; remplissage `Theme.accentStrong` ; largeur max du libellé 116 ; **slot sans icône** : si `symbol.isEmpty`, pas d'icône, libellé en 13 pt semibold, une ligne, centré verticalement sur le point d'ancrage (`y: center.y - 9, height: 18`) ;
    - centre : nom et compteur en 11 pt ;
    - titre : indices inactifs en `secondaryLabelColor`.
  - `WheelController` :
    - `reloadItems()` : message vide composé `model.mode.emptyMessage` + pour Convertir et Outils une seconde ligne `"\(triggers.key(for: .actions).glyph)\u{00A0}Actions reste disponible"` (triggers = `SettingsStore.triggers`) ;
    - annonces : à l'ouverture (`show`) et après `navigate`/`switchMode` : `Announcer.say("\(model.title), \(count) choix")` (ou le message vide) ; dans `setHoveredSlot` quand `slot` non nil : `Announcer.say("\(item.title), \(slot + 1) sur \(count)")`.
- [ ] **Step 4 : tests + build + rendus roue (convertir survolé, sous-roue, actions, vide) clair/sombre ; mesurer blanc sur #B8532F.**
- [ ] **Step 5 : commit** `Phase 7: wheel contrast, VoiceOver announcements, quieter details`.

---

### Task 3 : icônes cohérentes et typographie française

**Files :** `ImageFormat.swift`, `ImageToWebPOperation.swift`, `MediaOutput.swift`, `AirDropAction.swift`, `ResizeOperation.swift`, puis toutes les chaînes d'interface françaises de `App/` · Tests touchés : `ResizeOperationTests`, toute comparaison de chaîne.

- [ ] **Step 1 : icônes** — règle : toute image matricielle = `photo` (JPG, PNG, HEIC, TIFF, AVIF, BMP, WebP) ; PDF `doc.text` ; MP4/MOV `film` ; GIF `photo.stack` ; audio inchangé ; AirDrop `dot.radiowaves.left.and.right` (pas de symbole AirDrop public, vérifié) ; préréglages de redimensionnement : `symbol` vide (libellé seul, le parent garde `aspectratio`).
- [ ] **Step 2 : typographie** — espace fine insécable U+202F avant « : ? ! », espace insécable U+00A0 entre nombre et unité (« 1920\u{00A0}px », « 50\u{202F}% »), apostrophe typographique ’ dans les textes affichés, « Afficher dans le\u{00A0}Finder ». Uniquement dans les littéraux affichés (vues, messages d'erreur, titres), jamais dans les journaux techniques, identifiants ou arguments ffmpeg. Tests : `ResizePreset` titres attendus `["50\u{202F}%", "1920\u{00A0}px", "1280\u{00A0}px", "800\u{00A0}px"]`, les `alreadySmall(than:)` des tests utilisent `ResizePreset.long1920.title`.
- [ ] **Step 3 : tests + build + rendus.**
- [ ] **Step 4 : commit** `Phase 7: one icon rule, French typography`.

---

### Task 4 : onboarding et Réglages — l'accompagnement jusqu'au bout

**Files :** `App/Settings/OnboardingView.swift`, `GestureAnimationView.swift`, `SettingsModel.swift`, `SettingsView.swift`, `App/AppDelegate.swift`, `App/GestureCoordinator.swift`

- [ ] **Step 1 :**
  - pages 2 et 3 : `.frame(maxWidth: .infinity, alignment: .leading)` sur leurs VStack ;
  - page 1 : touches écrites en entier (`TriggerKey.name`, ex. « ⇧ Maj ») au-dessus du nom de la roue ; texte « Pendant que vous glissez un fichier, appuyez brièvement sur une touche\u{202F}: la roue s’ouvre autour du curseur. Lâchez le fichier sur une action. » ;
  - permission : « Indispensable\u{202F}: repère la touche appuyée pendant que vous glissez un fichier. » ;
  - animation : boucle de 5 s qui montre aussi le dépôt (le document glisse vers le segment allumé, la roue se ferme) puis une mini-pastille « photo.png créé » ; image fixe (roue ouverte, segment allumé) sous « Réduire les animations » ;
  - fin : `GestureCoordinator.inform(_:symbol:)` → `JobQueue.inform` ; à « Terminer », pastille « Pivot est prêt\u{202F}: glissez un fichier, puis appuyez brièvement sur ⇧\u{00A0}Maj. » (touche lue dans `SettingsStore.triggers`) ;
  - Réglages, section Général : bouton « Revoir la présentation » (`SettingsModel.onReplayOnboarding`), qui ferme les Réglages et rouvre l'onboarding à l'écran 1 (nouvelle fenêtre à chaque fois).
- [ ] **Step 2 : build + tests + rendus des 3 écrans et des Réglages, clair/sombre.**
- [ ] **Step 3 : commit** `Phase 7: onboarding that finishes the job, replay from Settings`.

---

### Task 5 : vérification et nouvelle critique

- [ ] verification-before-completion : tests, build, signature, CPU au repos, contrastes mesurés sur les nouveaux rendus (blanc sur #B8532F, indices inactifs, nom au centre, pastille).
- [ ] Nouvelle critique Impeccable (deux évaluations isolées) pour mesurer l'écart avec 24/40 ; clôture de l'instantané traité (`critique-storage close`) si les priorités sont soldées.
- [ ] CLAUDE.md (phase 7), commit, push, résumé + checklist manuelle (VoiceOver, Réduire les animations, survol de la pastille, clair/sombre).
