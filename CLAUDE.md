# Pivot — notes pour Claude Code

- La spécification complète est dans `SPEC.md` : la lire au début de chaque session et la suivre (règles de travail §1, phases §9).
- Build : `scripts/build.sh [Debug|Release]` (XcodeGen + xcodebuild). Lancer : `open build/Build/Products/Debug/Pivot.app`.
- Tests unitaires : `scripts/test.sh` (cible PivotTests sans app hôte).
- Debug sans drag : `open -n Pivot.app --args -debugWheel convert|tools|actions [-debugSlot N] [-debugSnapshot out.png]` (rendu hors écran : sans matériau HUD ni échelle de survol).
- Signature ad hoc ⇒ l’autorisation Accessibilité saute à chaque build : `tccutil reset Accessibility local.pivot.app`, relancer, réautoriser.
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
| 2. Geste + roue factice | 🟡 Geste réel validé par Raphaël ; zone morte au bord de la roue corrigée (rayon de détection 152 pt, 21 tests OK) ; reste à confirmer le bord à la main, puis go phase 3 |
| 3 à 8 | ⏳ Pas commencées |

## Décisions en attente

- Nom définitif (proposés : Orbe, Virage, Halo, Pivot, Rondo).
- Couleur d'accent (proposées : terracotta `#D9663F`, ambre `#E0A030`).
