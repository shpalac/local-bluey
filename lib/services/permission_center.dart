/// A deterministic permission grant owned by the permission center.
class PermissionGrant {
  PermissionGrant({required this.id, this.expiresAtMs});

  final String id;
  final int? expiresAtMs;
  bool _revoked = false;

  bool get isRevoked => _revoked;

  void revoke() => _revoked = true;

  bool isActive(int nowMs) =>
      !_revoked && (expiresAtMs == null || nowMs < expiresAtMs!);
}

/// Core permission registry shared by watchdog/policy/ephemeral grants.
class PermissionCenter {
  PermissionCenter({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, PermissionGrant> _grants = {};
  final Set<String> _baseline = {};
  final Set<String> _allowlist = {};

  List<PermissionGrant> get grants => List.unmodifiable(_grants.values);

  void setWatchdogBaseline(Iterable<String> permissions) {
    _baseline
      ..clear()
      ..addAll(permissions);
  }

  void setAppAllowlist(Iterable<String> apps) {
    _allowlist
      ..clear()
      ..addAll(apps);
  }

  PermissionGrant grant(String id, {Duration? expiry}) {
    final grant = PermissionGrant(
      id: id,
      expiresAtMs: expiry == null
          ? null
          : _now().add(expiry).millisecondsSinceEpoch,
    );
    _grants[id] = grant;
    return grant;
  }

  void revoke(String id) {
    _grants[id]?.revoke();
  }

  bool allows(String id) {
    final grant = _grants[id];
    if (grant != null) return grant.isActive(_now().millisecondsSinceEpoch);
    return _baseline.contains(id) || _allowlist.contains(id);
  }
}
