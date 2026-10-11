import 'dart:async';

import 'package:flutter/material.dart';

import '../services/strings.dart';
import '../services/tray_publication_caller.dart';

/// In-app recovery only, not guaranteed reachable while the window is hidden.
class TrayPublicationNotice extends StatelessWidget {
  const TrayPublicationNotice({super.key, required this.caller});
  final TrayPublicationCaller caller;
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
                      'Tray update pending. Tray state is not verified.',
                      'עדכון מגש בהמתנה. מצב המגש לא אומת.',
                    )
                  : Strings.t(
                      'Could not complete tray update. Tray state is not verified.',
                      'לא ניתן להשלים עדכון מגש. מצב המגש לא אומת.',
                    ),
            ),
            actions: [
              TextButton(
                onPressed: caller.loading
                    ? null
                    : () => unawaited(caller.request(explicitRetry: true)),
                child: Text(
                  caller.loading
                      ? Strings.t('Pending...', 'בהמתנה...')
                      : Strings.t('Retry tray', 'ניסיון מגש חוזר'),
                ),
              ),
            ],
          ),
  );
}
