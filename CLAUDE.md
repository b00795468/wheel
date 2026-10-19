# Pivot — notes pour Claude Code

- La spécification complète est dans `SPEC.md` : la lire au début de chaque session et la suivre (règles de travail §1, phases §9).
- Build : `scripts/build.sh [Debug|Release]` (XcodeGen + xcodebuild). Lancer : `open build/Build/Products/Debug/Pivot.app`.
- Tests unitaires : `scripts/test.sh` (cible PivotTests sans app hôte).
- ffmpeg : `scripts/fetch-ffmpeg.sh` (appelé automatiquement par build.sh et test.sh) récupère le build martin-riedl.de 9.0.2 arm64 validé par Raphaël, SHA-256 épinglés, dans `Vendor/ffmpeg/` (non versionné) ; la phase de build « Embed ffmpeg » le copie dans `Contents/Resources/bin/` et le re-signe.
- Debug sans drag : `open -n Pivot.app --args -debugWheel convert|tools|actions [-debugSlot N] [-debugSnapshot out.png] [-debugFiles '("/chemin")']` (rendu hors écran : sans matériau HUD ni échelle de survol) ; `-debugRun convert.png -debugFiles '("/chemin")'` exécute une opération comme après un drop.
- Journal technique des échecs : `~/Library/Logs/Pivot/Pivot.log`. Vérifier les invites de confidentialité : `log show --predicate 'subsystem == "com.apple.TCC" AND eventMessage CONTAINS "pid=<PID>"'`.
- Signature : `build.sh` signe avec le certificat local auto-signé « Pivot Dev » s’il existe (l’autorisation Accessibilité survit alors aux builds), sinon en ad hoc (à réautoriser après chaque build : `tccutil reset Accessibility local.pivot.app`). Écart assumé au §3, validé par Raphaël.
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
| 4. ffmpeg + audio/vidéo | 🟡 Code fait (plan : `docs/superpowers/plans/2026-10-19-phase-4-ffmpeg-media.md`), 85 tests OK, conversions réelles via `-debugRun` (HEVC→MP4, GIF, MP3), ffmpeg arrêté à l’annulation et à la fermeture ; à valider : checklist manuelle (vrai drag, 3 vidéos en parallèle, grosse vidéo, invites) |
| 5 à 8 | ⏳ Pas commencées |

## Décisions en attente

- Nom définitif (proposés : Orbe, Virage, Halo, Pivot, Rondo).
- Couleur d'accent (proposées : terracotta `#D9663F`, ambre `#E0A030`).
