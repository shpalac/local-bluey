import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The one place this app configures platform secure storage.
///
/// The macOS plugin defaults to the data-protection keychain, which refuses
/// every write from an app without a keychain-access-groups entitlement
/// (-34018 errSecMissingEntitlement). That entitlement needs a provisioning
/// profile with the Keychain Sharing capability, so a locally signed build
/// cannot obtain it and every secure-storage write fails. The classic login
/// keychain needs no entitlement and stores the same values.
///
/// Every call site goes through here. A bare `FlutterSecureStorage()` is the
/// shape that reintroduces the bug, and
/// `test/secure_storage_options_test.dart` fails the build when one returns.
FlutterSecureStorage secureStorage() => const FlutterSecureStorage(
  mOptions: MacOsOptions(useDataProtectionKeyChain: false),
);
