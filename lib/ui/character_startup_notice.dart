import 'dart:async';

import 'package:flutter/material.dart';

import '../services/character_startup.dart';
import '../services/strings.dart';

/// Safe caller failure and explicit retry, independent of retained character choice.
class CharacterStartupNotice extends StatelessWidget {
  /// Uses the lifecycle owner shared by the character startup caller.
  const CharacterStartupNotice({super.key, required this.controller});

  /// Caller failure/retry state, not storage verification or character reset.
  final CharacterStartup controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.failed) return const SizedBox.shrink();
      return MaterialBanner(
        content: Text(
          Strings.t(
            controller.verified
                ? 'Character load failed. Current character retained.'
                : 'Character load failed. Current character retained; saved choice unverified.',
            controller.verified
                ? 'טעינת הדמות נכשלה. הדמות הנוכחית נשמרה.'
                : 'טעינת הדמות נכשלה. הדמות נשמרה; הבחירה השמורה לא אומתה.',
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
