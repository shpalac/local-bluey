# Bundled and harness fonts

Two font files were added or replaced for the screenshot refresh (#279).

## Roboto Regular (bundled in the app)

- File: `assets/fonts/Roboto-Regular.ttf`, license: `assets/fonts/LICENSE-Roboto.txt` (Apache License 2.0).
- Version: Roboto 2.137 (font name table), copyright 2011 Google Inc.
- Source: the `material_fonts` artifact of the Flutter SDK used by this repo's CI and tooling (Flutter 3.47.6, engine `692136cb6582dbfc5af3fb33c2515a069f2f66d0`), path `bin/cache/artifacts/material_fonts/Roboto-Regular.ttf`.
- SHA-256: `79e851404657dac2106b3d22ad256d47824a9a5765458edb72c9102a45816d95`

Asset-only change: before this change the file on `main` was an HTML page saved with a `.ttf` name, not a font. Replacing it with the real Roboto changes what the app bundles and what text rendering falls back to for that family. The font is applied by the app theme exactly as before. No code, theme or layout was changed for it.

## Noto Sans Hebrew Regular (test and screenshot harness only)

- File: `test/screenshots/fonts/NotoSansHebrew-Regular.ttf`, license: `test/screenshots/fonts/OFL-NotoSansHebrew.txt` (SIL Open Font License 1.1, text from https://github.com/googlefonts/noto-fonts/blob/main/LICENSE).
- Version: 3.000 (font name table), copyright 2019 Google Inc.
- Source: Debian package `fonts-noto-core` 20201225-1build1, file `/usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf`. Upstream project: https://github.com/notofonts/hebrew.
- SHA-256: `436900d5ad77d33e4234247f3076eaecd25b92b9bea0519514f684140e3566a7`

This file is loaded only by the screenshot harness for the Hebrew right-to-left captures. It is not listed in `pubspec.yaml` and is not shipped in the app.
