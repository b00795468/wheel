# Pivot — notes pour Claude Code

- La spécification complète est dans `SPEC.md` : la lire au début de chaque session et la suivre (règles de travail §1, phases §9).
- Build : `scripts/build.sh [Debug|Release]` (XcodeGen + xcodebuild). Lancer : `open build/Build/Products/Debug/Pivot.app`.
- Tests unitaires : `scripts/test.sh` (cible PivotTests sans app hôte).
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
| 4 à 8 | ⏳ Pas commencées |

## Décisions en attente

- Nom définitif (proposés : Orbe, Virage, Halo, Pivot, Rondo).
- Couleur d'accent (proposées : terracotta `#D9663F`, ambre `#E0A030`).
