import 'dart:async';

import 'package:flutter/material.dart';

import '../services/appearance_startup.dart';
import '../services/strings.dart';

/// Safe caller failure and explicit retry, independent of retained appearance mode.
class AppearanceStartupNotice extends StatelessWidget {
  /// Uses the lifecycle owner shared by the appearance startup caller.
  const AppearanceStartupNotice({super.key, required this.controller});

  /// Caller failure/retry state, not storage verification or theme reset.
  final AppearanceStartup controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.failed) return const SizedBox.shrink();
      return MaterialBanner(
        content: Text(
          Strings.t(
            'Could not load appearance settings. Current appearance is retained.',
            'לא ניתן לטעון את הגדרות המראה. המראה הנוכחי נשמר.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: controller.loading
                ? null
                : () => unawaited(controller.retry()),
            child: Text(
              controller.loading
                  ? Strings.t('Retrying...', 'מנסה שוב...')
                  : Strings.t('Retry', 'ניסיון חוזר'),
            ),
          ),
        ],
      );
    },
  );
}
