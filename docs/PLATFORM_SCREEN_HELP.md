# Platform screen help

This page explains which screen Local Bluey opens on each operating system, and what the "does not support this platform yet" screen does and does not tell you. It is based on the current source (`SupportMatrix`, `homeForProfile`, `UnsupportedScreen`) and the existing support and screen tests. It claims no backend, OS or device result beyond that.

## Which screen you get

The app picks its first screen from a support matrix by operating system, not from scattered platform checks.

| Operating system | Role in the matrix | First screen |
|---|---|---|
| macOS | host | the Mac home |
| iOS | phone client | the phone remote, behind the app lock gate |
| Android | phone client | the phone remote, behind the app lock gate |
| Linux | unsupported | "Local Bluey does not support this platform yet" |
| Windows | unsupported | the same unsupported screen |
| Any other or unknown system | unsupported | the same unsupported screen |

An unsupported system never gets the host or phone-remote screens.

## The unsupported screen

It shows:

- a title, "Local Bluey does not support this platform yet";
- a reason. For Linux and Windows it says "This platform can be neither a host nor a remote client." For an unknown system it says "This operating system (name) is not recognized.";
- the line "Supported today: macOS as the host, iPhone and Android as remotes.";
- the address of the README platform-support section, as selectable text. It is text, not a button.

The screen starts no network, audio or discovery work. There is no action on it to switch roles, activate a profile or change a setting. To use Bluey, use a supported device from the line above.

## What the matrix does and does not mean

- The matrix lists capabilities per system. Linux and Windows list hold-to-talk, but their role is still unsupported, so the app shows the unsupported screen and does not offer a microphone or running UI there.
- Linux has experimental host-control code. That does not turn the Linux role into a host: the matrix keeps it unsupported and the app still shows the unsupported screen. See the Linux host modes in [SUPPORT.md](SUPPORT.md#linux-host-modes-150-151), which keep their own limits (untested on a real desktop, compositor differences). This page does not confirm them.
- A capability in the matrix describes the source's role choice only. It is not proof that the OS, a backend or a particular device works.
- The matrix has no display-switching or profile-activation step, and no guarantee about hardware or network.

## Source and tests

- Roles and capabilities: [`lib/services/support_matrix.dart`](../lib/services/support_matrix.dart)
- Screen choice: `homeForProfile` in [`lib/main.dart`](../lib/main.dart)
- Unsupported screen: [`lib/ui/unsupported_screen.dart`](../lib/ui/unsupported_screen.dart)
- Tests: [`test/support_matrix_test.dart`](../test/support_matrix_test.dart), [`test/unsupported_screen_test.dart`](../test/unsupported_screen_test.dart)
- Matrix table: [SUPPORT.md](SUPPORT.md)
