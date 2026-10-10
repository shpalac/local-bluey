import 'dart:async';

import 'package:flutter/material.dart';

import '../services/language_startup.dart';
import '../services/strings.dart';

/// Safe caller failure and explicit retry, independent of retained UI and speech choices.
class LanguageStartupNotice extends StatelessWidget {
  /// Uses the lifecycle owner shared by the language startup caller.
  const LanguageStartupNotice({super.key, required this.controller});

  /// Caller failure/retry state, not storage verification or language reset.
  final LanguageStartup controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.failed) return const SizedBox.shrink();
      return MaterialBanner(
        content: Text(
          Strings.t(
            'Language load failed. UI and speech choices retained; saved values unverified.',
            'טעינת השפה נכשלה. בחירות הממשק והדיבור נשמרו; הערכים השמורים לא אומתו.',
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
