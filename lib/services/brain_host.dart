import 'package:flutter/foundation.dart';

import '../llm/brain.dart';
import 'settings_store.dart';

/// Holds the live brain, rebuilt whenever settings change. Other slices
/// (transcription, tool executor) read [brain] instead of constructing
/// their own providers.
class BrainHost {
  BrainHost._();

  static final ValueNotifier<Brain?> brain = ValueNotifier(null);

  /// Loads saved settings and (re)builds the brain. Safe to call again after
  /// the user edits settings.
  static Future<void> reload() async {
    final settings = await SettingsStore.load();
    brain.value = settings.buildBrain();
  }
}
