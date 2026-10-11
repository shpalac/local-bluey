import 'dart:async';

import 'package:flutter/material.dart';

import '../services/key_cleanup_caller.dart';
import '../services/strings.dart';

/// Independent retained cleanup action, not a recording Stop or request bubble.
class KeyCleanupNotice extends StatelessWidget {
  const KeyCleanupNotice({super.key, required this.caller});
  final KeyCleanupCaller caller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: caller,
    builder: (context, _) => !caller.visible
        ? const SizedBox.shrink()
        : MaterialBanner(
            forceActionsBelow: MediaQuery.sizeOf(context).width < 600,
            content: Text(
              Strings.t(
                'Key recording cleanup is not verified. Retry cleanup only; no audio is sent and no recording starts.',
                'ניקוי ההקלטה מהמקש לא אומת. ניסיון חוזר לניקוי בלבד; לא נשלח שמע ולא מתחילה הקלטה.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: caller.enabled
                    ? () => unawaited(caller.retry())
                    : null,
                child: Text(
                  caller.loading
                      ? Strings.t('Retrying...', 'מנסה שוב...')
                      : Strings.t('Retry cleanup', 'ניסיון ניקוי חוזר'),
                ),
              ),
            ],
          ),
  );
}
