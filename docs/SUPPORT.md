# Platform support matrix (#51)

Role is chosen by capability (SupportMatrix), not Platform.isMacOS checks.

| Platform | Role | Host control | Window mgmt | Hold-to-talk | Phone server | Mac link |
|---|---|---|---|---|---|---|
| macOS | host | yes | yes | yes | yes | yes |
| iOS | phone client | - | - | yes | - | yes |
| Android | phone client | - | - | yes | - | yes |
| Linux | unsupported | - | - | yes | - | - |
| Windows | unsupported | - | - | yes | - | - |

A new host platform graduates from `unsupported` by implementing
HostControl (#52) and flipping its profile here. A new client only needs
hold-to-talk + the Mac link.

## Linux host modes (#150, #151)

Linux host control is best-effort and mode-dependent
(`HostControl.linuxHostMode` reports the active mode for onboarding and
troubleshooting):

| Mode | Capture | Input | Notes |
|---|---|---|---|
| X11 | import (ImageMagick) | xdotool | full backend (#150) |
| Wayland (portal) | org.freedesktop.portal.Screenshot, one-shot with consent dialog | ydotool only, opt-in uinput setup | drag/scroll/region-crop not yet implemented |
| no display | - | - | unsupported screen |

Wayland compatibility (untested until the device pass #125; portal behavior
varies by compositor):

| Compositor | Screenshot portal | Input (ydotool) |
|---|---|---|
| GNOME | expected to work | expected with udev rule |
| KDE Plasma | expected to work | expected with udev rule |
| wlroots (Sway etc.) | expected to work | expected with udev rule |

Denied portal consent surfaces as a clean tool error, not a hang.
