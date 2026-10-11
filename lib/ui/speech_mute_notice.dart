import 'dart:async';

import 'package:flutter/material.dart';

import '../services/speech_mute_caller.dart';
import '../services/strings.dart';

/// Independent local failure/pending notice, not remote mute confirmation.
class SpeechMuteNotice extends StatelessWidget {
  const SpeechMuteNotice({super.key, required this.caller});
  final SpeechMuteCaller caller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: caller,
    builder: (context, _) => !caller.visible
        ? const SizedBox.shrink()
        : MaterialBanner(
            forceActionsBelow: MediaQuery.sizeOf(context).width < 600,
            content: Text(
              caller.loading
                  ? Strings.t(
                      'Stopping speech on this Mac. Phone mute is not verified.',
                      'עוצר דיבור ב-Mac הזה. ההשתקה בטלפון לא אומתה.',
                    )
                  : Strings.t(
                      'Could not verify speech stopped on this Mac. Phone mute is not verified.',
                      'לא ניתן לאמת שהדיבור נעצר ב-Mac הזה. ההשתקה בטלפון לא אומתה.',
                    ),
            ),
            actions: [
              TextButton(
                onPressed: caller.loading
                    ? null
                    : () => unawaited(caller.mute()),
                child: Text(
                  caller.loading
                      ? Strings.t('Stopping...', 'עוצר...')
                      : Strings.t('Retry mute', 'ניסיון השתקה חוזר'),
                ),
              ),
            ],
          ),
  );
}
