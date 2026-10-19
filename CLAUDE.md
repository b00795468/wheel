# Pivot — notes pour Claude Code

- La spécification complète est dans `SPEC.md` : la lire au début de chaque session et la suivre (règles de travail §1, phases §9).
- Build : `scripts/build.sh [Debug|Release]` (XcodeGen + xcodebuild). Lancer : `open build/Build/Products/Debug/Pivot.app`.
- Réponds-moi en français ; code et commentaires en anglais.
- À la fin de chaque phase : compiler, lancer, vérifier, commit, mettre à jour l'état ci-dessous, puis attendre mon « go ».

## État d'avancement

| Phase | État |
|---|---|
| §2 Environnement | ✅ macOS 27.0.1, arm64, Xcode 27.1, Homebrew 7.0.9, XcodeGen installé |
| 1. Squelette | ✅ Compile (Debug), testée : lancement LSUIElement, Réglages au 1er lancement et à la réouverture (sur l’espace actif), bouton Quitter, CPU 0 % au repos |
| 2 à 8 | ⏳ Pas commencées |

## Décisions en attente

- Nom définitif (proposés : Orbe, Virage, Halo, Pivot, Rondo).
- Couleur d'accent (proposées : terracotta `#D9663F`, ambre `#E0A030`).
