# Spécification — Convertisseur de fichiers « zéro clic » pour macOS (nom de code Pivot)

## 0. Contexte et rôle

Tu es un ingénieur macOS senior (Swift, AppKit, SwiftUI). Tu vas construire **de zéro** une application macOS native, à usage personnel, inspirée de l'ergonomie de Tangerine (tangerineformac.com) : un convertisseur de fichiers 100 % local, piloté par un geste.

**Le geste signature :** l'utilisateur commence à glisser un fichier (depuis le Finder ou le bureau), **tape** une touche modificatrice, et une **roue radiale** apparaît autour du curseur. Il lâche le fichier sur un segment de la roue → l'action s'exécute. La roue reste ouverte jusqu'au drop ou à l'annulation, même après avoir relâché la touche.

- **⇧ Shift** → roue « Convertir » (formats de sortie)
- **⌘ Command** → roue « Outils » (compresser, redimensionner…)
- **⌃ Control** → roue « Actions » (copier le chemin, révéler, AirDrop)
- Pendant que la roue est ouverte, taper une autre de ces touches bascule vers la roue correspondante.

**Philosophie :** sobre, discret, extrêmement fluide. L'app est **invisible** (pas d'icône Dock, pas d'icône barre de menus) et ne se manifeste que pendant le geste. Ce n'est PAS une copie de marque : nom, icône et couleur d'accent sont originaux (voir §6).

L'app sera **compilée sur mon Mac puis envoyée à mon frère** (un autre Mac Apple Silicon). Elle doit donc être **autonome** : aucune dépendance installée sur sa machine (pas de Homebrew chez lui).

---

## 1. Règles de travail (à respecter tout au long)

1. **Avance par phases** (§9). À la fin de chaque phase : compile, lance, vérifie, fais un commit git, puis **arrête-toi et résume-moi** ce qui marche, ce qui reste, et comment le tester. Attends mon « go » avant la phase suivante.
2. **Demande-moi avant** d'installer quoi que ce soit sur ma machine (Homebrew, XcodeGen, binaires).
3. Ne prétends jamais qu'une chose fonctionne sans l'avoir compilée et testée. Si un test manuel est nécessaire (geste de drag réel), donne-moi une checklist précise à exécuter.
4. Code propre, commenté là où c'est non évident, aucune « magic string » dispersée. Pas de dépendance tierce Swift sauf justification forte (l'objectif est zéro package externe).
5. Si une hypothèse de ce document s'avère techniquement fausse (API indisponible, comportement macOS différent), **dis-le-moi** et propose l'alternative au lieu de bricoler en silence.
6. Langue de l'interface : **français**. Code, noms de types et commentaires : anglais.

---

## 2. Vérification de l'environnement (avant d'écrire du code)

Exécute et rapporte :

```bash
sw_vers                      # macOS ≥ 14 requis
uname -m                     # doit être arm64
xcodebuild -version          # Xcode installé et licence acceptée
xcode-select -p              # doit pointer vers Xcode.app, pas CommandLineTools
git --version
brew --version               # Homebrew (pour XcodeGen côté build uniquement)
```

Si quelque chose manque, arrête-toi et dis-moi exactement quoi faire (ex. `sudo xcode-select -s /Applications/Xcode.app`, `sudo xcodebuild -license accept`).

---

## 3. Stack et choix techniques imposés

- **Langage :** Swift 5.9+ ; **UI :** AppKit pour la roue et la gestion des événements globaux, SwiftUI pour la fenêtre Réglages et l'onboarding.
- **Cible :** macOS 14.0+, **arm64 uniquement**.
- **Projet :** généré avec **XcodeGen** (`project.yml` versionné, `.xcodeproj` dans `.gitignore`) pour que tout soit pilotable en ligne de commande. Build via `xcodebuild`.
- **Pas d'App Sandbox** (l'app doit lire des fichiers arbitraires, lancer ffmpeg et surveiller les événements globaux). Hardened Runtime désactivé ou compatible avec l'exécution du binaire embarqué.
- **Signature :** ad hoc (« Sign to Run Locally », `CODE_SIGN_IDENTITY = "-"`). Pas de notarisation.
- **`Info.plist` :** `LSUIElement = YES` (aucune icône Dock/menu), `NSAppleEventsUsageDescription` si besoin (sélection Finder, §5.6), descriptions en français.
- **Moteurs de conversion :**
  - Images : **ImageIO / CoreImage** (lecture HEIC, JPG, PNG, TIFF, WebP, AVIF ; écriture JPG, PNG, HEIC, TIFF). L'écriture **WebP** n'étant pas assurée par ImageIO : la faire via ffmpeg embarqué (si compilé avec libwebp) — **vérifie-le** et sinon embarque `cwebp` statique.
  - PDF : **PDFKit** (pages → PNG/JPG à 300 DPI ; images → PDF multipage).
  - Audio / vidéo / GIF : **ffmpeg statique arm64 embarqué** dans `Contents/Resources/bin/ffmpeg` (+ `ffprobe`).
    - Récupère un build statique arm64 fiable (ex. martin-riedl.de ou osxexperts.net — demande-moi avant de télécharger), vérifie avec `otool -L` qu'il ne dépend **que** de bibliothèques système (aucun `/opt/homebrew`), vérifie qu'il a h264/hevc (VideoToolbox), aac, libmp3lame, libwebp.
    - Le binaire est signé ad hoc lors du build (phase de build « Run Script ») et son attribut quarantaine retiré.
    - Encodage vidéo matériel via `h264_videotoolbox` / `hevc_videotoolbox` quand possible.
    - Progression lue via `-progress pipe:1` + durée via `ffprobe`.

---

## 4. Architecture attendue

```
App/
  AppDelegate.swift            // cycle de vie, LSUIElement, réouverture → Réglages
  DragMonitor/
    DragSessionMonitor.swift   // détecte un drag système en cours + fichiers concernés
    ModifierTapDetector.swift  // détecte un "tap" de touche modificatrice pendant le drag
  Wheel/
    WheelPanel.swift           // NSPanel transparent, non activant, au-dessus de tout
    WheelView.swift            // dessin radial, hit-testing, highlight, animations
    WheelDropTarget.swift      // NSDraggingDestination : survol segment, drop
    WheelModel.swift           // segments, mode courant (convert/tools/actions), pagination
  Operations/
    Operation.swift            // protocole commun
    OperationRegistry.swift    // catalogue : quelles opérations pour quels UTType
    Converters/ImageConverter.swift, PDFConverter.swift, MediaConverter.swift
    Tools/CompressTool.swift, ResizeTool.swift
    Actions/CopyPathAction.swift, RevealAction.swift, AirDropAction.swift
    Engines/FFmpegRunner.swift // Process, progression, annulation
  Output/
    OutputLocator.swift        // dossier de sortie, nommage, collisions
    JobQueue.swift             // file d'exécution, concurrence limitée, annulation
  Feedback/
    HUDToast.swift             // petite pastille de confirmation près du curseur
  Settings/
    SettingsStore.swift        // UserDefaults typés
    SettingsView.swift         // SwiftUI
    OnboardingView.swift       // permissions au premier lancement
  Permissions/
    PermissionsManager.swift   // Accessibilité, Surveillance de l'entrée, état + liens Réglages
Tests/
  OperationTests/, OutputLocatorTests/, Fixtures/
```

**Protocole central (à adapter mais garder l'esprit) :**

```swift
protocol FileOperation {
    var id: String { get }                 // "convert.png", "tool.compress"…
    var kind: OperationKind { get }        // .convert / .tool / .action
    var title: String { get }              // "PNG", "Compresser"
    var symbol: String { get }             // SF Symbol
    func accepts(_ types: [UTType]) -> Bool
    func run(inputs: [URL], context: OperationContext,
             progress: @escaping (Double) -> Void) async throws -> [URL]
}
```

**Ajouter un format = ajouter une entrée dans le registre**, sans toucher à la roue. C'est le critère d'extensibilité principal.

---

## 5. Spécification fonctionnelle détaillée

### 5.1 Détection du geste
- Détecter le début d'un drag système : surveiller `NSPasteboard(name: .drag).changeCount` combiné à un moniteur global `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp, .flagsChanged])`. Lire les `fileURL` présents dans le pasteboard de drag.
- **Tap** = la touche modificatrice est pressée puis relâchée en < 400 ms, sans autre touche entre-temps, **pendant** qu'un drag de fichier(s) est actif. Un simple maintien de ⌘ pour forcer « déplacer » dans le Finder ne doit **pas** ouvrir la roue s'il n'y a pas de relâchement rapide → à valider en test.
- Au tap : afficher la roue **centrée sur le curseur** (clampée dans le `visibleFrame` de l'écran courant, multi-écrans géré).
- Fin du drag (mouseUp) hors de la roue ou appui sur **Échap** → la roue se ferme sans rien faire. Le fichier source ne doit jamais être déplacé/supprimé.
- Touches remappables dans les Réglages (Shift / Command / Control / Option pour chacune des 3 roues).

### 5.2 La roue
- `NSPanel` borderless, `nonactivatingPanel`, niveau au-dessus des apps et du Dock, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`, fond transparent, n'apparaît pas dans Mission Control. Ne vole jamais le focus de l'app au premier plan.
- Accepte les drops de `fileURL` ; renvoie l'opération `.copy` pour que la source reste intacte.
- Disposition : anneau d'environ **280 pt** de diamètre, **6 à 8 segments max** par page. Au-delà : un segment « Plus… » qui fait tourner/paginer vers les options suivantes au survol prolongé (500 ms).
- **Centre** de la roue = zone neutre / annulation. Affiche l'icône du fichier, son nom tronqué, et « ×3 » si plusieurs fichiers.
- Petit titre au-dessus de l'anneau : « Convertir », « Outils » ou « Actions », avec rappel discret des touches pour basculer (⇧ ⌘ ⌃).
- Survol d'un segment : surbrillance avec la couleur d'accent, légère mise à l'échelle (1.0 → 1.06), retour haptique trackpad (`NSHapticFeedbackManager`, `.alignment`).
- Segments non applicables (ex. conversion impossible pour ce type) : non affichés. Si aucune conversion n'existe : la roue « Convertir » affiche un message neutre « Aucune conversion pour ce type » et la roue « Actions » reste accessible.
- Fichiers multiples : n'afficher que les opérations applicables à **tous** les fichiers. Dossiers : uniquement les actions.
- Apparition : fondu + scale 0.92 → 1 en ~140 ms (ressort doux). Disparition : ~100 ms. Respecter **Réduire les animations**.
- Matériau : `NSVisualEffectView` (`.hudWindow` ou `.popover`), coins arrondis, ombre légère ; parfait en mode clair et sombre.
- Libellés courts (« PNG », « MP3 », « Compresser »), SF Symbols cohérents, typo système.

### 5.3 Mode clavier (secondaire)
- Raccourci global configurable (défaut **⌃⌥Espace**) : récupère la sélection courante du Finder (AppleScript / `NSAppleScript` → permission Automatisation), ouvre la roue au centre de l'écran actif.
- Flèches ←/→ (ou ↑/↓) pour naviguer, **Entrée** pour appliquer, **Échap** pour annuler, ⇧/⌘/⌃ pour changer de roue.

### 5.4 Périmètre des opérations (v1)

**⇧ Convertir**
| Entrée | Sorties |
|---|---|
| JPG, PNG, HEIC, WebP, TIFF, AVIF, BMP | JPG, PNG, HEIC, WebP, TIFF, PDF |
| PDF | PNG, JPG (toutes les pages, 300 DPI ; une page → un fichier ; plusieurs → sous-dossier) |
| Plusieurs images | PDF (fusion multipage, dans l'ordre du drag) |
| MP4, MOV, MKV, WebM, AVI | MP4 (H.264), MOV, GIF (palette optimisée, 15 fps, largeur max 720), MP3, M4A |
| MP3, M4A, WAV, FLAC, AIFF, OGG | MP3 (192k), M4A (AAC 256k), WAV, FLAC |

Ne pas proposer la conversion vers le format d'origine.

**⌘ Outils**
- **Compresser** : images (JPG qualité 75 %, PNG → optimisation sans perte si possible), vidéo (H.264/HEVC VideoToolbox, ~1080p, débit raisonnable), PDF (`PDFDocument` réécrit avec images downsamplées si faisable — sinon le reporter en v2 et me le dire). Le nom de sortie prend le suffixe ` (compressé)`.
- **Redimensionner** (images, vidéo) : sous-roue avec préréglages **50 %**, **1920 px**, **1280 px**, **800 px** (plus grand côté, ratio conservé).

**⌃ Actions**
- **Copier le chemin** (chemin POSIX, plusieurs fichiers séparés par des retours à la ligne).
- **Afficher dans le Finder**.
- **AirDrop** (`NSSharingService(named: .sendViaAirDrop)`).

### 5.5 Sortie des fichiers
- Dossier par défaut : **`~/Downloads/Convertis/`** (créé si absent). Option dans les Réglages : « Dossier personnalisé… » ou « À côté de l'original ».
- Nom : même nom de base + nouvelle extension. Collision → `nom 2.ext`, `nom 3.ext`… **Jamais d'écrasement, jamais de modification de l'original.**
- Écriture d'abord dans un fichier temporaire puis déplacement atomique.
- Préserver les métadonnées utiles (date de création, orientation EXIF corrigée) ; ne pas propager la géolocalisation si l'option « Retirer les données de localisation » est cochée (désactivée par défaut).

### 5.6 Exécution et retour
- File d'attente (`JobQueue`) : max 2 tâches médias en parallèle, images en parallèle illimité raisonnable. Lancer une nouvelle opération pendant qu'une autre tourne = mise en file, pas de blocage.
- **Retour visuel** : petite pastille HUD (sans permission de notification) près du coin bas-droit de l'écran : icône + « photo.png créé » ; clic → révèle dans le Finder ; disparaît après 3 s. Pour les tâches > 1 s : la pastille montre une barre de progression et un bouton d'annulation.
- Erreurs : message humain en français (« Ce fichier vidéo semble corrompu »), jamais de stack trace. Log technique dans `~/Library/Logs/<NomApp>/`.
- Son système discret à la fin (désactivable).

### 5.7 Réglages, onboarding, permissions
- L'app n'a aucune présence visible. **La rouvrir** (Spotlight, dossier Applications, double-clic) ouvre la fenêtre **Réglages** (`applicationShouldHandleReopen` + premier lancement).
- **Onboarding au premier lancement** (SwiftUI, 3 écrans max) :
  1. Le geste expliqué en une animation simple.
  2. Permissions : **Accessibilité** et **Surveillance de l'entrée** — état en direct (✓ / à faire), bouton qui ouvre directement le bon panneau des Réglages Système, détection automatique quand c'est accordé.
  3. Choix du dossier de sortie + « Ouvrir au démarrage » (coché par défaut, via `SMAppService.mainApp`).
- **Réglages** : touches des 3 roues, raccourci clavier, dossier de sortie, ouvrir au démarrage, son, retrait de la localisation, qualité par défaut (Standard / Haute), état des permissions, bouton « Quitter l'application », version.

---

## 6. Identité visuelle

- **Nom :** propose-moi 5 noms courts et originaux (pas « Tangerine » ni dérivés d'agrumes trop proches), j'en choisirai un. En attendant, utilise le nom de code `Pivot`.
- **Couleur d'accent :** une seule, chaude et sobre, à proposer (2 options) — utilisée uniquement pour le segment survolé et la progression.
- **Icône d'app :** simple, géométrique (un anneau segmenté stylisé), générée en SVG → `.icns` via `iconutil`. Rien qui ressemble au logo Tangerine.
- Ton général : minimal, aucune fioriture, aucun texte superflu.

---

## 7. Tests et qualité

- **Tests unitaires** (XCTest) pour : chaque convertisseur (fixtures générées par script : `sips`, `ffmpeg -f lavfi testsrc`, `sine`), `OutputLocator` (collisions, dossier absent, noms avec accents/espaces/emoji), registre (bonnes opérations pour bons types, intersection multi-fichiers).
- Vérifier sur chaque sortie : fichier lisible, bon format (`file`, `ffprobe`, `sips -g format`), taille non nulle.
- **Checklist de test manuel** à me fournir à chaque phase, incluant : drag depuis le Finder, depuis le bureau, depuis une fenêtre Finder en plein écran, deuxième écran, ⌘ maintenu sans tap (ne doit pas ouvrir), Échap, drop hors roue, fichier sans conversion, dossier, 10 fichiers d'un coup, vidéo de 2 Go (annulation), mode sombre/clair.
- Performance : la roue doit apparaître en **< 100 ms** après le tap ; aucun impact CPU mesurable au repos (pas de polling agressif — si un polling du pasteboard est nécessaire, uniquement pendant un mouseDragged actif).

---

## 8. Livraison pour mon frère

À la fin, produis :
1. `dist/Pivot.app` (build Release, arm64, ffmpeg embarqué et signé ad hoc).
2. `dist/Pivot.zip` créé avec `ditto -c -k --keepParent` (préserve la signature).
3. `dist/INSTALLATION.md` **et** sa version PDF, en français simple, pour quelqu'un de non technique :
   - Copier l'app dans **Applications**.
   - Premier lancement bloqué → **Réglages Système → Confidentialité et sécurité → « Ouvrir quand même »** (avec capture ou description précise ; macOS 15+ n'accepte plus le clic droit → Ouvrir).
   - Accorder **Accessibilité** et **Surveillance de l'entrée** (l'onboarding guide).
   - Le geste en 3 lignes + tableau des touches.
   - Comment ouvrir les Réglages (relancer l'app) et comment quitter.
   - Dépannage : la roue n'apparaît pas → vérifier les permissions, retirer/remettre l'app dans la liste, redémarrer l'app.
4. Vérifie avant de livrer : `codesign -dv --verbose=2`, `otool -L` sur ffmpeg, lancement depuis un autre compte utilisateur macOS ou après `xattr -w com.apple.quarantine` pour simuler la machine de mon frère.

---

## 9. Phases

1. **Squelette** : environnement vérifié, `project.yml`, app LSUIElement qui se lance, fenêtre Réglages vide à la réouverture, commit.
2. **Geste + roue factice** : détection drag + tap, roue affichée au curseur avec segments factices, survol/haptique, drop → log du fichier et du segment, Échap/annulation. **C'est la phase la plus critique : prends le temps de la rendre parfaite avant d'aller plus loin.**
3. **Registre + conversions images & PDF** (natif, sans ffmpeg), sortie dans `Downloads/Convertis`, pastille HUD.
4. **ffmpeg embarqué** + conversions audio/vidéo/GIF, progression, annulation, file d'attente.
5. **Outils** (compresser, redimensionner) et **Actions** (chemin, Finder, AirDrop).
6. **Onboarding, permissions, Réglages complets, mode clavier.**
7. **Finitions** : identité visuelle, animations, accessibilité, tests, performances.
8. **Livraison** (§8).

**Critère de réussite final :** mon frère installe l'app avec le guide, sans aide, et le geste drag → tap → drop fonctionne de façon fluide et fiable depuis le Finder, sans jamais toucher à ses fichiers originaux.
