import 'dart:async';

import 'package:flutter/material.dart';

import '../services/strings.dart';
import '../services/trust_observation.dart';

/// Independent status checks; only verified denial offers the explicit action.
class TrustObservationNotice extends StatelessWidget {
  const TrustObservationNotice({
    super.key,
    required this.caller,
    required this.openSettings,
  });
  final TrustObservation caller;
  final Future<void> Function() openSettings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: caller,
    builder: (context, _) {
      if (caller.status == TrustObservationStatus.granted) {
        return const SizedBox.shrink();
      }
      final denied = caller.status == TrustObservationStatus.denied;
      final text = switch (caller.status) {
        TrustObservationStatus.denied => Strings.t(
          'Local Bluey needs Accessibility permission to point and click.',
          'לבלואי נדרשת הרשאת נגישות כדי להצביע וללחוץ.',
        ),
        TrustObservationStatus.loading => Strings.t(
          'Checking Accessibility status. No permission is requested.',
          'בודק את מצב הנגישות. לא מתבקשת הרשאה.',
        ),
        TrustObservationStatus.failed => Strings.t(
          'Could not check Accessibility status. Current permission is unverified.',
          'לא ניתן לבדוק את מצב הנגישות. ההרשאה הנוכחית לא אומתה.',
        ),
        _ => Strings.t(
          'Accessibility status has not been checked.',
          'מצב הנגישות עדיין לא נבדק.',
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
          if (denied)
            TextButton(
              onPressed: () => unawaited(openSettings()),
              child: Text(Strings.t('Open settings', 'פתיחת הגדרות')),
            ),
        ],
      );
    },
  );
}
