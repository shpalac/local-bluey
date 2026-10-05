/// Joins an endpoint base URL and a path without producing `//` when the
/// saved base has a trailing slash (#118). Also trims surrounding whitespace
/// so a pasted URL with a stray space still parses.
String endpoint(String base, String path) {
  final cleanBase = base.trim().replaceAll(RegExp(r'/+$'), '');
  final cleanPath = path.startsWith('/') ? path : '/$path';
  return '$cleanBase$cleanPath';
}
