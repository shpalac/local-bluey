import 'package:shared_preferences/shared_preferences.dart';

/// Whether the screen watcher may observe what is currently in front (#212).
enum WatchVerdict {
  /// Observation allowed: session on, app allowlisted, nothing hard-denied.
  allow,

  /// App is simply not on the user's allowlist. Not counted as an exclusion.
  notAllowlisted,

  /// App is on the hard deny list (password managers, banking, system
  /// surfaces). Always denied, even if the user allowlisted it by name.
  hardDenied,

  /// A private/incognito browser window is in front.
  privateWindow,

  /// The screen is locked.
  locked,
}

/// Allowlist + hard deny list for proactive screen watching (#212).
///
/// The user picks the apps that may be observed. The hard deny list always
/// wins - it exists so a mistake or a prompt-injected allowlist entry can
/// never open observation on the most sensitive surfaces.
class WatchPolicy {
  WatchPolicy._();

  static const _kAllowlist = 'watch.appAllowlist';
  static const _kUserDenylist = 'watch.appUserDenylist';

  /// Apps that are never observed, even if allowlisted (#212).
  /// Matched lowercase against the frontmost app name/bundle.
  static const hardDenyApps = {
    // Password managers and keychains.
    '1password',
    'bitwarden',
    'dashlane',
    'keepassxc',
    'keepass',
    'lastpass',
    'enpass',
    'keychain access',
    // System surfaces.
    'system settings',
    'system preferences',
    'loginwindow',
  };

  /// Substrings that mark a banking/payment app or site title. Matched
  /// lowercase against app name AND window title.
  static const hardDenySubstrings = [
    'bank',
    'hapoalim',
    'leumi',
    'mizrahi',
    'discount',
    'mercantile',
    'isracard',
    'pepper',
    'one zero',
    'bit.co.il',
    'paybox',
    // Hebrew banking terms (#212): Hebrew window titles carry no Latin
    // 'bank' to match.
    'בנק',
    'מזרחי',
    'דיסקונט',
    'ישראכרט',
    'פפר',
  ];

  /// Window-title markers of a private browsing window, per browser (#212).
  static const privateWindowMarkers = [
    'incognito', // Chrome
    'private browsing', // Safari / Firefox
    'private window', // Firefox
    'inprivate', // Edge
    'גלישה פרטית', // Hebrew Chrome/Firefox
    'חלון פרטי', // Hebrew Safari
  ];

  /// Canonical app identity for consent and policy comparisons.
  static String normalize(String name) {
    var n = name.trim().toLowerCase();
    if (n.endsWith('.app')) n = n.substring(0, n.length - 4);
    return n;
  }

  /// The user's allowlist (app names, normalized).
  static Future<List<String>> allowlist() async =>
      (await SharedPreferences.getInstance()).getStringList(_kAllowlist) ??
      const [];

  /// Adds [app] to the user allowlist (no-op if already there).
  static Future<void> addToAllowlist(String app) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [...?prefs.getStringList(_kAllowlist)];
    final n = normalize(app);
    if (n.isEmpty || list.contains(n)) return;
    list.add(n);
    await prefs.setStringList(_kAllowlist, list);
  }

  /// Removes [app] from the user allowlist.
  static Future<void> removeFromAllowlist(String app) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [...?prefs.getStringList(_kAllowlist)]..remove(normalize(app));
    await prefs.setStringList(_kAllowlist, list);
  }

  /// The user's own extra deny list, on top of the hard list.
  static Future<List<String>> userDenylist() async =>
      (await SharedPreferences.getInstance()).getStringList(_kUserDenylist) ??
      const [];

  /// Adds [app] to the user's extra deny list (no-op if already there).
  static Future<void> addToUserDenylist(String app) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [...?prefs.getStringList(_kUserDenylist)];
    final n = normalize(app);
    if (n.isEmpty || list.contains(n)) return;
    list.add(n);
    await prefs.setStringList(_kUserDenylist, list);
  }

  static bool _isHardDenied(String appNorm, String? windowTitle) {
    if (hardDenyApps.contains(appNorm)) return true;
    final title = (windowTitle ?? '').toLowerCase();
    for (final marker in hardDenySubstrings) {
      if (appNorm.contains(marker) || title.contains(marker)) return true;
    }
    return false;
  }

  static bool _isPrivateWindow(String? windowTitle) {
    final title = (windowTitle ?? '').toLowerCase();
    if (title.isEmpty) return false;
    return privateWindowMarkers.any(title.contains);
  }

  /// The decision for the app/window currently in front. Hard denies are
  /// checked before the allowlist so they always win (#212).
  static Future<WatchVerdict> verdict({
    required String frontApp,
    String? windowTitle,
    bool locked = false,
    List<String>? allowedApps,
    List<String>? deniedApps,
  }) async {
    if (locked) return WatchVerdict.locked;
    if (_isPrivateWindow(windowTitle)) return WatchVerdict.privateWindow;
    final app = normalize(frontApp);
    if (_isHardDenied(app, windowTitle)) return WatchVerdict.hardDenied;
    final userDeny = (deniedApps ?? await userDenylist())
        .map(normalize)
        .toSet();
    if (userDeny.contains(app)) return WatchVerdict.hardDenied;
    final allowed = (allowedApps ?? await allowlist()).map(normalize).toSet();
    return allowed.contains(app)
        ? WatchVerdict.allow
        : WatchVerdict.notAllowlisted;
  }
}
