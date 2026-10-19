# Pivot (nom de code)

Convertisseur de fichiers macOS « zéro clic » : glisser un fichier, taper ⇧/⌘/⌃, déposer sur la roue.

## Build (sur un Mac Apple Silicon, macOS 14+, Xcode)

```bash
brew install xcodegen      # une fois, côté build uniquement
scripts/build.sh           # Debug → build/Build/Products/Debug/Pivot.app (récupère ffmpeg au besoin)
open build/Build/Products/Debug/Pivot.app
scripts/test.sh            # tests unitaires
```

Le `.xcodeproj` est généré depuis `project.yml` et n'est pas versionné.

ffmpeg/ffprobe (build statique arm64 de martin-riedl.de, SHA-256 vérifiés) sont téléchargés par `scripts/fetch-ffmpeg.sh` dans `Vendor/ffmpeg/`, non versionné, puis embarqués dans l'app au build.

## Livraison

```bash
scripts/package.sh   # → dist/Pivot.app, dist/Pivot.zip, dist/INSTALLATION.md, dist/INSTALLATION.pdf
```

À envoyer : `Pivot.zip` et `INSTALLATION.pdf`. Le guide source est `docs/INSTALLATION.md`.
