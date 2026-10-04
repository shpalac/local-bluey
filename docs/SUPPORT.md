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
