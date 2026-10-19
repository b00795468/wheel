# Phase 8 — Livraison — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Ce projet impose `superpowers:executing-plans` (voir CLAUDE.md, section Skills).

**Goal :** produire `dist/Pivot.app` (Release, arm64, ffmpeg embarqué et signé), `dist/Pivot.zip`, `dist/INSTALLATION.md` et `dist/INSTALLATION.pdf`, puis vérifier le tout comme sur la machine du frère.

**Architecture :** un script reproductible `scripts/package.sh` enchaîne build Release (via `scripts/build.sh`), copie dans `dist/`, zip `ditto -c -k --keepParent`, guide Markdown → HTML (pandoc) → PDF (Chrome sans interface) et contrôles. La source du guide est versionnée dans `docs/INSTALLATION.md` (`dist/` est ignoré par git).

**Tech stack :** bash, xcodebuild/XcodeGen, ditto, codesign, otool, spctl, pandoc, Google Chrome `--headless --print-to-pdf`.

**Spec :** `SPEC.md` §8, §3 (signature), critère de réussite final (§9).

## Contraintes globales (§8)

1. `dist/Pivot.app` : build Release, arm64, ffmpeg embarqué et signé.
2. `dist/Pivot.zip` créé avec `ditto -c -k --keepParent` (préserve la signature).
3. `dist/INSTALLATION.md` **et** sa version PDF, en français simple, pour quelqu'un de non technique : copier dans Applications ; premier lancement bloqué → Réglages Système → Confidentialité et sécurité → « Ouvrir quand même » (macOS 15+ n'accepte plus clic droit → Ouvrir) ; accorder Accessibilité (l'onboarding guide) ; le geste en 3 lignes + tableau des touches ; rouvrir pour les Réglages, comment quitter ; dépannage (permissions, retirer/remettre l'app dans la liste, redémarrer l'app).
4. Vérifier : `codesign -dv --verbose=2`, `otool -L` sur ffmpeg, lancement après `xattr -w com.apple.quarantine` (simulation de la machine du frère).

**Écarts à signaler** : signature avec le certificat local « Pivot Dev » plutôt qu'ad hoc (même parcours Gatekeeper « Ouvrir quand même », mais l'autorisation Accessibilité du frère survivra aux futures mises à jour) — à confirmer par la vérification Gatekeeper ; « Surveillance de l'entrée » non demandée (phase 6) ; accent #F0F1F1.

---

### Task 1 : guide d'installation

**Files :** Create `docs/INSTALLATION.md`.

- [ ] Rédiger le guide (contenu exact ci-dessous), touches lues dans les valeurs par défaut (⇧ Maj, ⌘ Commande, ⌃ Contrôle, ⌃⌥Espace).

```markdown
# Installer Pivot

Pivot convertit vos fichiers d’un simple geste : vous glissez un fichier, vous appuyez brièvement sur une touche, une roue apparaît, vous lâchez le fichier sur ce que vous voulez en faire. Tout se passe sur votre Mac, rien n’est envoyé sur Internet, et vos fichiers d’origine ne sont jamais modifiés.

## 1. Copier Pivot dans Applications

1. Double-cliquez sur **Pivot.zip** : un fichier **Pivot** apparaît à côté.
2. Faites glisser **Pivot** dans le dossier **Applications** (dans le Finder, colonne de gauche).

## 2. Ouvrir Pivot la première fois

Pivot ne vient pas de l’App Store : la première fois, macOS le bloque par prudence. C’est normal.

1. Dans **Applications**, double-cliquez sur **Pivot**. Un message dit qu’Apple n’a pas pu vérifier l’app. Cliquez sur **Terminé** (ou **OK**).
2. Ouvrez **Réglages Système** (menu Apple › Réglages Système…), puis **Confidentialité et sécurité** dans la colonne de gauche.
3. Descendez jusqu’à la ligne « **Pivot a été bloqué…** » et cliquez sur **Ouvrir quand même**.
4. Tapez votre mot de passe de session si on vous le demande, puis cliquez sur **Ouvrir**.

Vous n’aurez à faire cela qu’une seule fois.

## 3. Suivre la présentation

Au premier lancement, une fenêtre « Bienvenue dans Pivot » s’ouvre.

- **Écran 1** : le geste, en animation.
- **Écran 2** : les autorisations.
  - **Accessibilité (indispensable)** : cliquez sur **Autoriser…**. Dans la fenêtre de Réglages Système qui s’ouvre, activez l’interrupteur à côté de **Pivot**. Revenez à la présentation : la ligne passe à « Autorisé » toute seule.
  - **Contrôle du Finder (facultatif)** : sert seulement au raccourci clavier. Cliquez sur **Autoriser…** puis sur **OK** dans le message de macOS.
- **Écran 3** : choisissez où ranger les fichiers convertis (par défaut : **Téléchargements › Convertis**) et laissez « Ouvrir Pivot au démarrage » coché. Cliquez sur **Terminer**.

Une petite bulle « Pivot est prêt » apparaît en bas à droite de l’écran. Pivot n’a ni icône dans le Dock ni dans la barre des menus : il attend simplement votre geste.

## 4. Le geste

1. Commencez à **glisser** un fichier (depuis le Finder ou le bureau), sans le lâcher.
2. **Appuyez brièvement** sur une touche (appuyer puis relâcher tout de suite) : une roue apparaît autour du curseur.
3. **Lâchez** le fichier sur l’action voulue.

| Touche | Roue | Exemples |
|---|---|---|
| ⇧ Maj | Convertir | JPG, PNG, PDF, MP4, MP3… |
| ⌘ Commande | Outils | Compresser, Redimensionner |
| ⌃ Contrôle | Actions | Copier le chemin, Afficher dans le Finder, AirDrop |

- Pendant que la roue est ouverte, appuyez sur une autre de ces touches pour changer de roue.
- Pour annuler : lâchez le fichier au centre de la roue, en dehors de la roue, ou appuyez sur **Échap**.
- Le résultat arrive dans le dossier choisi (par défaut **Téléchargements › Convertis**). Une bulle en bas à droite le confirme : cliquez dessus pour voir le fichier.
- Sans glisser : sélectionnez des fichiers dans le Finder et appuyez sur **⌃⌥Espace** (Contrôle + Option + Espace). Les flèches choisissent, **Entrée** applique, **Échap** annule.

## 5. Réglages et quitter

- **Ouvrir les réglages** : ouvrez Pivot à nouveau (dossier Applications, ou ⌘ Espace puis tapez « Pivot »).
- **Quitter** : dans les réglages, bouton **Quitter Pivot** en bas à droite. Pour le relancer, ouvrez-le simplement.

## 6. Si la roue n’apparaît pas

1. Vérifiez l’autorisation : **Réglages Système › Confidentialité et sécurité › Accessibilité**, l’interrupteur à côté de **Pivot** doit être activé.
2. S’il est activé mais que rien ne se passe : sélectionnez **Pivot** dans cette liste, cliquez sur **–** pour le retirer, puis sur **+** pour le remettre (choisissez Pivot dans Applications) et réactivez l’interrupteur.
3. Quittez Pivot (réglages › Quitter Pivot) et ouvrez-le à nouveau.
4. Pensez à appuyer **brièvement** sur la touche pendant que le fichier est en train d’être glissé : maintenir la touche enfoncée ne fait rien.

Si macOS vous demande l’accès au dossier Téléchargements ou au Bureau, cliquez sur **Autoriser** : c’est là que Pivot lit et range les fichiers.
```

- [ ] Commit `Phase 8: installation guide (source)`.

---

### Task 2 : script de livraison

**Files :** Create `scripts/package.sh` (+x).

```bash
#!/bin/bash
# Builds the deliverables for Raphaël's brother (SPEC §8) into dist/:
# Pivot.app (Release, arm64, ffmpeg embedded and signed), Pivot.zip,
# INSTALLATION.md and INSTALLATION.pdf, then runs the delivery checks.
# Usage: scripts/package.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
command -v pandoc >/dev/null || { echo "pandoc manquant (sert au PDF du guide)" >&2; exit 1; }
[ -x "$CHROME" ] || { echo "Google Chrome manquant (sert au PDF du guide)" >&2; exit 1; }

scripts/build.sh Release
rm -rf dist
mkdir -p dist
ditto build/Build/Products/Release/Pivot.app dist/Pivot.app
# ditto keeps the signature, extended attributes and the app bundle intact.
(cd dist && ditto -c -k --keepParent Pivot.app Pivot.zip)

cp docs/INSTALLATION.md dist/INSTALLATION.md
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pandoc docs/INSTALLATION.md -s -o "$TMP/INSTALLATION.html" --metadata title="Installer Pivot" \
  -c "file://$PWD/docs/installation.css"
"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
  --print-to-pdf="$PWD/dist/INSTALLATION.pdf" "file://$TMP/INSTALLATION.html" 2>/dev/null

echo "== Signature"
codesign --verify --deep --strict dist/Pivot.app && echo "signature valide"
codesign -dv --verbose=2 dist/Pivot.app 2>&1 | grep -E '^(Identifier|Authority|Signature|TeamIdentifier)='
codesign -dv --verbose=2 dist/Pivot.app/Contents/Resources/bin/ffmpeg 2>&1 | grep -E '^(Authority|Signature)='
echo "== Architecture et dépendances de ffmpeg"
lipo -archs dist/Pivot.app/Contents/MacOS/Pivot
if otool -L dist/Pivot.app/Contents/Resources/bin/ffmpeg dist/Pivot.app/Contents/Resources/bin/ffprobe | grep -E '/opt/|/usr/local/'; then
  echo "Dépendance non système" >&2; exit 1
fi
echo "ffmpeg et ffprobe : bibliothèques système uniquement"
echo "== Livrables"
ls -lh dist
```

`docs/installation.css` : mise en page sobre pour le PDF (A4, police système, tableaux lisibles).

```css
@page { size: A4; margin: 18mm 18mm 20mm; }
body { font: 11pt/1.5 -apple-system, "Helvetica Neue", sans-serif; color: #1d1d1f; max-width: none; }
h1 { font-size: 22pt; margin: 0 0 6pt; }
h2 { font-size: 14pt; margin: 18pt 0 6pt; page-break-after: avoid; }
p, li { orphans: 3; widows: 3; }
table { border-collapse: collapse; width: 100%; margin: 8pt 0; page-break-inside: avoid; }
th, td { border-bottom: 1px solid #d2d2d7; padding: 5pt 8pt; text-align: left; }
th { font-weight: 600; }
strong { font-weight: 600; }
header#title-block-header { display: none; }
```

- [ ] Exécuter `scripts/package.sh` ; attendu : signature valide (`Authority=Pivot Dev`), arm64, aucune dépendance non système, `dist/` contient Pivot.app, Pivot.zip, INSTALLATION.md, INSTALLATION.pdf. Lire le PDF (pages rendues) pour vérifier la mise en page.
- [ ] Commit `Phase 8: packaging script`.

---

### Task 3 : simulation de la machine du frère

- [ ] Dans un dossier temporaire : extraire `dist/Pivot.zip` avec `ditto -x -k`, poser l'attribut de quarantaine comme un téléchargement (`xattr -w com.apple.quarantine "0081;<horodatage hex>;Safari;" Pivot.app` récursivement), puis `spctl --assess --type execute -vv` (attendu : refusé, comme toute app non notarisée → c'est le cas « Ouvrir quand même » du guide) et comparer avec un build ad hoc pour confirmer que le certificat « Pivot Dev » ne change pas le parcours.
- [ ] Prévenir Raphaël avant un lancement réel avec quarantaine (une boîte de dialogue Gatekeeper apparaîtra sur son écran) ; vérifier dans le journal système que le blocage est bien celui attendu ; nettoyer le dossier temporaire.

### Task 4 : vérification finale et documentation

- [ ] verification-before-completion : tests, `scripts/package.sh` complet, relecture des 4 contraintes du §8 ligne par ligne.
- [ ] CLAUDE.md (phase 8), README (section livraison), commit, push, résumé à Raphaël avec ce qu'il envoie à son frère (Pivot.zip + INSTALLATION.pdf) et les tests à faire de son côté.
