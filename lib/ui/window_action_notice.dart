import 'dart:async';

import 'package:flutter/material.dart';

import '../services/strings.dart';
import '../services/window_action_caller.dart';

/// Reachable only when the app is visible; no hidden-window recovery promise.
class WindowActionNotice extends StatelessWidget {
  const WindowActionNotice({super.key, required this.caller});
  final WindowActionCaller caller;
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
                      'Window action pending. Window state is not verified.',
                      'פעולת חלון בהמתנה. מצב החלון לא אומת.',
                    )
                  : caller.failed == WindowIntent.show
                  ? Strings.t(
                      'Could not complete Show. Window state is not verified.',
                      'לא ניתן להשלים הצגה. מצב החלון לא אומת.',
                    )
                  : Strings.t(
                      'Could not complete Hide. Window state is not verified.',
                      'לא ניתן להשלים הסתרה. מצב החלון לא אומת.',
                    ),
            ),
            actions: [
              TextButton(
                onPressed: caller.loading
                    ? null
                    : () => unawaited(caller.request(caller.failed!)),
                child: Text(
                  caller.loading
                      ? Strings.t('Pending...', 'בהמתנה...')
                      : caller.failed == WindowIntent.show
                      ? Strings.t('Retry Show', 'ניסיון הצגה חוזר')
                      : Strings.t('Retry Hide', 'ניסיון הסתרה חוזר'),
                ),
              ),
            ],
          ),
  );
}
