import 'package:flutter/foundation.dart';

import '../llm/brain.dart';
import 'privacy_guard.dart';
import 'settings_store.dart';

/// Holds the live brain, rebuilt whenever settings change. Other slices
/// (transcription, tool executor) read [brain] instead of constructing
/// their own providers.
class BrainHost {
  BrainHost._();

  /// The active brain; null until the first [reload] completes.
  static final ValueNotifier<Brain?> brain = ValueNotifier(null);

  /// Loads saved settings and (re)builds the brain. Safe to call again after
  /// the user edits settings.
  /// Set when local-only mode refused a remote provider; the UI shows it
  /// as the clear "data would leave the Mac" indicator.
  static final ValueNotifier<String?> refusedReason = ValueNotifier(null);

  /// True when the current provider talks off-device.
  static final ValueNotifier<bool> remoteActive = ValueNotifier(false);

  /// Loads saved settings and (re)builds the brain. Safe to call again
  /// after the user edits settings.
  static Future<void> reload() async {
    final settings = await SettingsStore.load();
    final refusal = await PrivacyGuard.refusal(settings);
    if (refusal != null) {
      refusedReason.value = refusal;
      remoteActive.value = false;
      brain.value = null;
      return;
    }
    refusedReason.value = null;
    remoteActive.value = !PrivacyGuard.isLocalUrl(settings.baseUrl);
    brain.value = settings.buildBrain();
  }
}
