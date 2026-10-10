import 'dart:async';

import 'package:flutter/material.dart';

import '../services/appearance_startup.dart';

/// Safe caller failure and explicit retry, independent of retained appearance mode.
class AppearanceStartupNotice extends StatelessWidget {
  /// Uses the lifecycle owner shared by all host reload callers.
  const AppearanceStartupNotice({super.key, required this.controller});

  /// Caller failure/retry state, not model or transport readiness.
  final AppearanceStartup controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.failed) return const SizedBox.shrink();
      return MaterialBanner(
        content: const Text(
          'Could not load appearance settings. Current appearance is retained.',
        ),
        actions: [
          TextButton(
            onPressed: controller.loading
                ? null
                : () => unawaited(controller.retry()),
            child: Text(controller.loading ? 'Retrying...' : 'Retry'),
          ),
        ],
      );
    },
  );
}
