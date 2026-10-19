# Pivot — notes pour Claude Code

- La spécification complète est dans `SPEC.md` : la lire au début de chaque session et la suivre (règles de travail §1, phases §9).
- Build : `scripts/build.sh [Debug|Release]` (XcodeGen + xcodebuild). Lancer : `open build/Build/Products/Debug/Pivot.app`.
- Tests unitaires : `scripts/test.sh` (cible PivotTests sans app hôte).
- ffmpeg : `scripts/fetch-ffmpeg.sh` (appelé automatiquement par build.sh et test.sh) récupère le build martin-riedl.de 9.0.2 arm64 validé par Raphaël, SHA-256 épinglés, dans `Vendor/ffmpeg/` (non versionné) ; la phase de build « Embed ffmpeg » le copie dans `Contents/Resources/bin/` et le re-signe.
- Debug sans drag : `open -n Pivot.app --args -debugWheel convert|tools|actions [-debugSlot N] [-debugSnapshot out.png] [-debugFiles '("/chemin")']` (rendu hors écran : sans matériau HUD ni échelle de survol) ; `-debugRun convert.png -debugFiles '("/chemin")'` exécute une opération comme après un drop ; `-debugKeyboard YES -debugFiles '("/chemin")'` ouvre la roue clavier ; `-debugSettingsSnapshot out.png` et `-debugOnboardingSnapshot out.png -debugOnboardingPage N` rendent les fenêtres hors écran (fond transparent : composer sur un fond sombre pour lire le texte blanc).
- Journal technique des échecs : `~/Library/Logs/Pivot/Pivot.log`. Vérifier les invites de confidentialité : `log show --predicate 'subsystem == "com.apple.TCC" AND eventMessage CONTAINS "pid=<PID>"'`.
- Signature : `build.sh` et `test.sh` (via `scripts/signing.sh`, car l’action de test recompile l’app) signent avec le certificat local auto-signé « Pivot Dev » s’il existe (l’autorisation Accessibilité survit alors aux builds), sinon en ad hoc (à réautoriser après chaque build : `tccutil reset Accessibility local.pivot.app`). Écart assumé au §3, validé par Raphaël.
- Revoir l’onboarding : `defaults delete local.pivot.app hasCompletedFirstLaunch` puis relancer.
- Réponds-moi en français ; code et commentaires en anglais.
- À la fin de chaque phase : compiler, lancer, vérifier, commit, mettre à jour l'état ci-dessous, puis attendre mon « go ».

## Skills

- Le spec est figé : **pas de brainstorming** (`superpowers:brainstorming` ne s'applique pas ici).
- Pour chaque phase : `superpowers:writing-plans`, puis `superpowers:executing-plans`.
- Si un build casse : `superpowers:systematic-debugging`.
- Avant de me résumer une phase : `superpowers:verification-before-completion`.
- Skills de design (impeccable, taste, cds-*, ui-ux-pro-max…) : **uniquement en phase 7** (finitions).

## État d'avancement

| Phase | État |
|---|---|
| §2 Environnement | ✅ macOS 27.0.1, arm64, Xcode 27.1, Homebrew 7.0.9, XcodeGen installé |
| 1. Squelette | ✅ Compile (Debug), testée : lancement LSUIElement, Réglages au 1er lancement et à la réouverture (sur l’espace actif), bouton Quitter, CPU 0 % au repos |
| 2. Geste + roue factice | ✅ Validée par Raphaël (geste réel, zones de drop sans zone morte) |
| 3. Registre + images & PDF | ✅ Validée par Raphaël (58 tests, conversions réelles, checklist manuelle OK). Sortie WebP reportée en phase 4 (ImageIO ne l’encode pas) |
| 4. ffmpeg + audio/vidéo | ✅ Go donné par Raphaël (85 tests, conversions réelles HEVC→MP4/GIF/MP3, ffmpeg arrêté à l’annulation et à la fermeture) |
| 5. Outils + Actions | ✅ Go donné par Raphaël. Code fait (plan : `docs/superpowers/plans/2026-10-19-phase-5-tools-actions.md`), 111 tests OK, essais réels (compression vidéo HEVC 1080p, redimensionnement, copie de chemin). Décisions : format conservé, jamais d’agrandissement, compression refusée si pas plus petite, BMP hors « Compresser », PDF via le filtre système « Reduce File Size » (les options PDFKit n’ont aucun effet ; liens/annotations perdus). |
| 6. Onboarding, Réglages, clavier | ✅ Validée par Raphaël (checklist OK). Code fait (plan : `docs/superpowers/plans/2026-10-19-phase-6-settings-onboarding-keyboard.md`), 121 tests OK ; mode clavier testé avec de vraies touches (→ puis Entrée, Échap) ; onboarding vérifié au premier lancement ; CPU 0 % au repos. Écart : « Surveillance de l’entrée » non demandée (jamais requise, mesuré). |
| 7. Finitions | 🟡 Critique Impeccable 24/40 → 27/40 puis seconde passe (onboarding sûr sans Accessibilité, pastille « dans <dossier> · Afficher », formats en libellés seuls, titre qui nomme les roues). Plans : `docs/superpowers/plans/2026-10-19-phase-7-polish.md`, critiques : `.impeccable/critique/`. 124 tests OK. À valider : checklist manuelle (VoiceOver, Réduire les animations, onboarding sans Accessibilité) |
| 8. Livraison | ⏳ Pas commencée |

## Décisions prises

- Nom : Pivot. Accent : `#F0F1F1` (choix de Raphaël, couleur préférée de son frère ; écart au §6 « chaude ») avec texte `#1D1D1F` dessus (14,9:1). La roue et les pastilles restent toujours en apparence sombre (`Theme.hudAppearance`), même en mode clair ; l’animation d’onboarding est sur un fond sombre ; le bouton « Autoriser… » garde l’accent système.
- Formats de la roue Convertir en libellés seuls ; noms de fichiers de sortie avec espaces ordinaires (pas d’insécables).
- « Afficher dans le Finder » : espace insécable avant « Finder », le libellé reste dans l’anneau (mesuré à 7,8 pt du bord).
