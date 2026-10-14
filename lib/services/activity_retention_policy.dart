import 'data_registry.dart';
import 'retention_purge.dart';

/// BLU-005: audited application policy for scoped activity deletion.
///
/// Never accept a caller-supplied classification for routines, settings,
/// pairing keys or downloaded models. Only known activity storage owners can
/// opt in here; all other current/future registry entries stay protected.
abstract final class ActivityRetentionPolicy {
  static const Map<String, RetentionClass> _approved = {
    'activity_store': RetentionClass.activity,
  };

  /// Only the audited encrypted database owner may be purged. Other stores
  /// (including credentials and routines) remain protected.
  static RetentionPurger fromRegistry(Iterable<DataStoreInfo> stores) {
    final classifications = <String, RetentionClass>{};
    for (final store in stores) {
      if (store.id == 'activity_store' &&
          store.sourceFile == 'lib/services/encrypted_activity_store.dart') {
        classifications[store.id] = _approved[store.id]!;
      }
    }
    return RetentionPurger.fromRegistry(stores, classes: classifications);
  }

  /// Production registry is the only source of store ownership. Do not
  /// register mutable user-supplied paths or ad-hoc deletion targets.
  static RetentionPurger forApplication() => fromRegistry(DataRegistry.stores);
}
