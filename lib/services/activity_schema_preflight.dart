import 'package:sqlite3/sqlite3.dart';

/// Read-only schema preflight before opening a writable activity database.
///
/// Versions newer than [supportedVersion] require an app upgrade. Old unknown
/// layouts require an explicit migration; neither may be silently initialized.
final class ActivitySchemaPreflight {
  const ActivitySchemaPreflight._();

  static void verify(Database database, {required int supportedVersion}) {
    final version =
        database.select('PRAGMA user_version').single.values.first as int;
    if (version > supportedVersion) {
      throw StateError('database requires a newer application version');
    }
    if (version < 0 || version < supportedVersion && version != 0) {
      throw StateError('database schema migration is unavailable');
    }
    if (version == 0 &&
        database.select(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%'",
        ).isNotEmpty) {
      throw StateError('unrecognized legacy database schema');
    }
  }
}
