# Pivot (nom de code)

Convertisseur de fichiers macOS « zéro clic » : glisser un fichier, taper ⇧/⌘/⌃, déposer sur la roue.

## Build (sur un Mac Apple Silicon, macOS 14+, Xcode)

```bash
brew install xcodegen      # une fois, côté build uniquement
scripts/build.sh           # Debug → build/Build/Products/Debug/Pivot.app
open build/Build/Products/Debug/Pivot.app
scripts/test.sh            # tests unitaires
```

Le `.xcodeproj` est généré depuis `project.yml` et n'est pas versionné.
