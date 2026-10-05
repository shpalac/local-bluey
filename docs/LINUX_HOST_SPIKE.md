# Linux host spike (#53)

Goal: run Bluey as the host on Linux. The Dart side already routes all
platform control through HostControl (#52); this spike maps each capability
to its Linux bridge.

| Capability | macOS bridge | Linux candidate | Risk |
|---|---|---|---|
| Screen capture | ScreenCaptureKit | PipeWire (Wayland) / X11 XGetImage | Wayland needs the portal + user consent each boot |
| OCR/targets | Vision + AX | tesseract over the capture; AT-SPI2 for the AX tree | AT-SPI2 coverage varies by app toolkit |
| Input | CGEvent | uinput (evdev) / xdotool (X11); ydotool (Wayland) | uinput needs root or an input-group udev rule |
| Open app/URL | NSWorkspace | xdg-open / gtk-launch | fine |
| Tray | tray_manager | tray_manager (AppIndicator) | needs libappindicator |
| Secure storage | Keychain | libsecret (flutter_secure_storage supports it) | fine |
| Window mgmt | window_manager | window_manager (Linux supported) | fine |

## Build check

`flutter create --platforms=linux .` then `flutter build linux` on a runner
with clang, cmake, ninja, gtk3 dev packages. Add a CI lane only after a
manual build succeeds once - unlike Android, the Linux build is not part of
this PR's CI.

## Permissions story

No accessibility API parity with macOS: input injection is udev/uinput,
screen capture is PipeWire portal consent. Both are one-time user grants,
persisted by the desktop portal.

## Verdict to fill in after first device run

- [ ] capture works on the target compositor
- [ ] uinput typing/click works without root
- [ ] tray icon shows

## Status update: linux/ runner exists (#149)

The `linux/` platform runner is generated and built in CI (`linux` job on
`ubuntu-latest`): GTK3/clang/cmake/ninja plus plugin system packages
libayatana-appindicator3-dev (tray_manager), libsecret-1-dev and
libjsoncpp-dev (flutter_secure_storage), libavahi-client-dev (nsd) and
libasound2-dev (record/audioplayers). Unit/widget tests run there too and
the release bundle is uploaded as a CI artifact. HostControl still returns
UnsupportedHostControl on Linux - the app shows the unsupported-host
screen; the X11 backend is #150.
