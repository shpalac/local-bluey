import 'safety_gate.dart';

/// A permission entry tracked by the center for lifecycle and expiry.
class PermissionGrant {
  PermissionGrant({required this.id, this.expiresAtMs});

  final String id;
  final int? expiresAtMs;
  bool _revoked = false;

  bool get isRevoked => _revoked;

  void revoke() => _revoked = true;

  bool isExpired(int nowMs) => expiresAtMs != null && nowMs >= expiresAtMs!;
}

/// Permission center facade over the existing safety authorization path.
///
/// The registry is only for grant lifecycle. Authorization is delegated to
/// SafetyGate so revocation changes the actual action decision path.
class PermissionCenter {
  PermissionCenter({required this.safetyGate, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final SafetyGate safetyGate;
  final DateTime Function() _now;
  final Map<String, PermissionGrant> _grants = {};

  List<PermissionGrant> get grants => List.unmodifiable(_grants.values);

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

  Future<bool> allows(String id) async {
    final grant = _grants[id];
    if (grant == null || grant.isRevoked) return false;
    if (grant.isExpired(_now().millisecondsSinceEpoch)) return false;
    return safetyGate.authorize(id, const {});
  }
}
