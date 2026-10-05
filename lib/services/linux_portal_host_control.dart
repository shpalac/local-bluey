import 'dart:async';
import 'dart:ui' show Offset;

import 'linux_host_base.dart';
import 'native_control.dart';

/// Wayland host control (#151): screenshot through the
/// org.freedesktop.portal.Screenshot D-Bus portal (user-consented, works on
/// GNOME/KDE/wlroots), input through ydotool as an opt-in advanced setup.
///
/// Wayland has no global input API. ydotool talks to uinput, which needs
/// root or an input-group udev rule - [StateError]s from input methods
/// explain that setup instead of failing opaquely.
///
/// Best-effort: portal behavior differs across compositors; tested targets
/// are listed in docs/SUPPORT.md.
class LinuxPortalHostControl extends LinuxHostControlBase {
  LinuxPortalHostControl({
    super.run,
    super.env,
    super.hasBinary,
    super.readBytes,
    super.makeTempDir,
  });

  static const _tools = {
    'gdbus': 'libglib2.0-bin',
    'convert': 'imagemagick',
    'tesseract': 'tesseract',
    'xdg-open': 'xdg-utils',
    'gtk-launch': 'libgtk-3-bin',
  };

  @override
  Map<String, String> get requiredTools => _tools;

  static const _inputExplainer =
      'Wayland input needs ydotool (uinput access). Install ydotool, then '
      'either run ydotoold as root or add a udev rule giving the input group '
      'access to /dev/uinput and add your user to that group. This grants '
      'system-wide input injection to every process running as you - only '
      'opt in if you accept that.';

  Future<bool> get hasInput => hasBinary('ydotool');

  @override
  Future<bool> isTrusted() async {
    // Portal screenshot needs only gdbus; input stays opt-in.
    return hasBinary('gdbus');
  }

  @override
  Future<void> askPermission() async {
    // Consent is per-request: the portal dialog appears on the first
    // screenshot. Nothing to pre-grant.
    if (!await hasBinary('gdbus')) {
      throw StateError(missingMessage(const ['gdbus']));
    }
  }

  Future<void> _requireInput() async {
    if (!await hasInput) throw StateError(_inputExplainer);
  }

  /// Calls a portal method and waits for its Response signal, returning the
  /// results dict as printed by gdbus. Portal requests are async: the call
  /// returns a request object path, and the answer arrives as a Response
  /// signal on that path.
  Future<String> _portalCall(
    String interface,
    String method,
    List<String> args,
  ) async {
    await requireTool('gdbus');
    final call = await run('gdbus', [
      'call',
      '--session',
      '--dest',
      'org.freedesktop.portal.Desktop',
      '--object-path',
      '/org/freedesktop/portal/desktop',
      '--method',
      '$interface.$method',
      ...args,
    ]);
    if (call.exitCode != 0) {
      throw StateError('portal $method failed: ${call.stderr}'.trim());
    }
    final out = '${call.stdout}';
    final requestPath = RegExp(
      "/org/freedesktop/portal/desktop/(request/[^'\")\\s]+)",
    ).firstMatch(out)?.group(1);
    if (requestPath == null) {
      // Synchronous-looking reply (some portals answer inline).
      return out;
    }
    // Wait for the Response signal carrying the results.
    final monitor =
        await run('gdbus', [
          'monitor',
          '--session',
          '--dest',
          'org.freedesktop.portal.Desktop',
          '--object-path',
          requestPath,
        ]).timeout(
          const Duration(seconds: 120),
          onTimeout: () {
            throw TimeoutException('portal $method: no response within 120s');
          },
        );
    final body = '${monitor.stdout}';
    if (body.contains('Response') && body.contains('(1,')) {
      throw StateError('portal $method was denied by the user.');
    }
    return body;
  }

  @override
  Future<ScreenSnapshot> snapshot() async {
    final body = await _portalCall(
      'org.freedesktop.portal.Screenshot',
      'Screenshot',
      ['', "{'interactive': <false>}"],
    );
    final uri = RegExp(r"'uri': <'([^']+)'").firstMatch(body)?.group(1);
    if (uri == null) {
      throw StateError('portal Screenshot returned no image uri: $body');
    }
    final path = Uri.parse(uri).toFilePath();
    // The portal PNG may be huge; downscale through convert.
    final dir = await makeTempDir();
    try {
      final jpg = '${dir.path}/shot.jpg';
      await ok('convert', [path, '-resize', '1280x>', '-quality', '80', jpg]);
      final small = await readBytes(jpg);
      final targets = await ocrTargets(path);
      // Portal gives us pixels; report the captured image size.
      final identify = await stdoutOf('convert', [
        path,
        '-format',
        '%w %h',
        'info:',
      ]);
      final parts = identify.trim().split(RegExp(r'\s+'));
      final w = double.tryParse(parts.first) ?? 0;
      final h = parts.length > 1 ? double.tryParse(parts[1]) ?? 0.0 : 0.0;
      return ScreenSnapshot(jpeg: small, targets: targets, width: w, height: h);
    } finally {
      await dir.delete(recursive: true);
    }
  }

  @override
  Future<ScreenSnapshot> snapshotRegion(
    double x,
    double y,
    double width,
    double height,
  ) {
    // The Screenshot portal has no region mode; capture-then-crop lands
    // with the device validation pass (#125). Full snapshot works today.
    throw UnsupportedError(
      'snapshotRegion is not implemented on Wayland yet: the Screenshot '
      'portal has no region mode (#151 follow-up).',
    );
  }

  @override
  Future<Offset> mouseLocation() {
    throw UnsupportedError(
      'Wayland does not expose the global pointer position. '
      'Targets come from snapshot OCR instead.',
    );
  }

  @override
  Future<void> warp(double x, double y) async {
    await _requireInput();
    await ok('ydotool', [
      'mousemove',
      '--absolute',
      '-x',
      '${LinuxHostControlBase.num_(x)}',
      '-y',
      '${LinuxHostControlBase.num_(y)}',
    ]);
  }

  @override
  Future<void> click(
    double x,
    double y, {
    bool right = false,
    int count = 1,
  }) async {
    await warp(x, y);
    // uinput button codes: 0xC0 left, 0xC1 right.
    final button = right ? '0xC1' : '0xC0';
    for (var i = 0; i < count; i++) {
      await ok('ydotool', ['click', button]);
    }
  }

  @override
  Future<void> drag(Offset from, Offset to) {
    throw UnsupportedError(
      'drag is not implemented on Wayland yet (#151 follow-up).',
    );
  }

  @override
  Future<void> scroll(double x, double y, {int dx = 0, int dy = 0}) {
    throw UnsupportedError(
      'scroll is not implemented on Wayland yet (#151 follow-up).',
    );
  }

  @override
  Future<void> type(String text) async {
    await _requireInput();
    await ok('ydotool', ['type', '--', text]);
  }

  /// Linux input-event codes for the keys Bluey presses (#151). Modifiers
  /// use the macOS names translated in [press].
  static const _keyCodes = {
    'ctrl': 29,
    'shift': 42,
    'alt': 56,
    'super': 125,
    'enter': 28,
    'escape': 1,
    'esc': 1,
    'tab': 15,
    'space': 57,
    'backspace': 14,
    'delete': 111,
    'up': 103,
    'down': 108,
    'left': 105,
    'right': 106,
    'home': 102,
    'end': 107,
    'pageup': 104,
    'pagedown': 109,
  };

  static int _codeFor(String key) {
    final named = _keyCodes[key];
    if (named != null) return named;
    if (key.length == 1) {
      final c = key.toLowerCase();
      const letters = 'abcdefghijklmnopqrstuvwxyz';
      const codes = [
        30,
        48,
        46,
        32,
        18,
        33,
        34,
        35,
        23,
        36,
        37,
        38,
        50,
        49,
        24,
        25,
        16,
        19,
        31,
        20,
        22,
        47,
        17,
        45,
        21,
        44,
      ];
      final i = letters.indexOf(c);
      if (i >= 0) return codes[i];
      const digits = '0123456789';
      const digitCodes = [11, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      final d = digits.indexOf(c);
      if (d >= 0) return digitCodes[d];
    }
    throw UnsupportedError('No evdev code mapped for key "$key" (#151).');
  }

  @override
  Future<String?> press(String combo) async {
    await _requireInput();
    final keys = combo
        .split('+')
        .map((k) => k.trim().toLowerCase())
        .map(
          (k) => switch (k) {
            'cmd' || 'meta' || 'win' => 'super',
            'option' => 'alt',
            'return' => 'enter',
            _ => k,
          },
        )
        .toList();
    if (keys.isEmpty) return null;
    final events = <String>[
      for (final k in keys) ...['${_codeFor(k)}:1'],
      for (final k in keys.reversed) ...['${_codeFor(k)}:0'],
    ];
    await ok('ydotool', ['key', ...events]);
    return keys.join('+');
  }
}
