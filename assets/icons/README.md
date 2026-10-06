# Bluey app icons

The owner selected the glowing blue face (option 1). `bluey-mobile.png` is the
1024px opaque square master, with the source's transparent gutter removed and
its blue background extended into the corners. iOS applies its own mask.
`bluey-desktop.png` is the 1024px transparent desktop master, with an inset
rounded tile. The face is the same on every platform.

Exports and wiring:

- Flutter iOS: all existing AppIcon sizes, including opaque 1024px marketing.
- Flutter macOS: all existing AppIcon sizes, 16px through 1024px.
- Native iOS: the same iOS catalog, added to both Xcode and XcodeGen resources.
- Native Mac: multiresolution `Mac/Resources/AppIcon.icns`, copied into the
  legacy bundle and selected by `CFBundleIconFile`.
- Android: mdpi through xxxhdpi legacy mipmaps and API 26+ adaptive layers.
  The adaptive face fits inside the 66dp safe area; the background is a blue
  gradient and the selected tile has feathered edges to avoid a hard seam.
- Linux: 16px through 512px hicolor icons plus generated desktop metadata.
  CMake installs both into the bundle's `share/` directory. The desktop file
  points to that configured installation path. After moving a bundle, rebuild
  with the new installation prefix or update the launcher paths before use.
- Flutter tray: the same desktop artwork at 64px on its existing asset path.

There are no web or Windows app targets in this checkout. No app behavior or
permissions were changed. Raster exports use Lanczos resampling.

Validation: inspect each platform export at native size, verify catalog
filename/dimension/scale matches, iOS RGB/no alpha, desktop transparent
corners, ICNS decoding, Android XML references and Linux installation paths.
Final checks still need Xcode/Android builds and real launchers: iPhone/iPad
home screen, Mac Finder/Dock/menu bar, Android round and squircle masks, and
Linux GNOME/KDE launcher association. The legacy Mac remains menu-bar-only.
