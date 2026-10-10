import 'dart:async';

import 'package:flutter/material.dart';

import '../services/host_reload_controller.dart';

/// Safe caller failure and explicit retry, independent of retained brain policy.
class HostReloadNotice extends StatelessWidget {
  /// Uses the lifecycle owner shared by all host reload callers.
  const HostReloadNotice({super.key, required this.controller});

  /// Caller failure/retry state, not model or transport readiness.
  final HostReloadController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.failed) return const SizedBox.shrink();
      return MaterialBanner(
        content: const Text(
          'Could not reload brain settings. Previous state is retained.',
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
