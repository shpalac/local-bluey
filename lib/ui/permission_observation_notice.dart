import 'dart:async';

import 'package:flutter/material.dart';

import '../services/strings.dart';
import '../services/permission_observation.dart';

/// Read-only recovery checks, independent of retained permission Fix/Later.
class PermissionObservationNotice extends StatelessWidget {
  const PermissionObservationNotice({super.key, required this.caller});
  final PermissionObservation caller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: caller,
    builder: (context, _) {
      if (caller.status == PermissionObservationStatus.current) {
        return const SizedBox.shrink();
      }
      final text = switch (caller.status) {
        PermissionObservationStatus.loading => Strings.t(
          'Checking permission recovery status. No permission is requested.',
          'בודק את מצב שחזור ההרשאות. לא מתבקשת הרשאה.',
        ),
        PermissionObservationStatus.failed => Strings.t(
          'Could not check permission recovery status. Previous recovery notices are retained; current permissions are unverified.',
          'לא ניתן לבדוק את מצב שחזור ההרשאות. הודעות קודמות נשמרות; ההרשאות הנוכחיות לא אומתו.',
        ),
        _ => Strings.t(
          'Permission recovery status has not been checked.',
          'מצב שחזור ההרשאות עדיין לא נבדק.',
        ),
      };
      return MaterialBanner(
        forceActionsBelow: MediaQuery.sizeOf(context).width < 600,
        content: Text(text),
        actions: [
          TextButton(
            onPressed: caller.loading ? null : () => unawaited(caller.check()),
            child: Text(
              caller.loading
                  ? Strings.t('Checking...', 'בודק...')
                  : Strings.t('Check status', 'בדיקת מצב'),
            ),
          ),
        ],
      );
    },
  );
}
