import 'dart:async';

import 'package:flutter/material.dart';

import '../services/strings.dart';
import '../services/trust_observation.dart';

/// Independent status checks; only verified denial offers the explicit action.
class TrustObservationNotice extends StatefulWidget {
  const TrustObservationNotice({
    super.key,
    required this.caller,
    required this.openSettings,
  });
  final TrustObservation caller;
  final Future<void> Function() openSettings;

  @override
  State<TrustObservationNotice> createState() => _TrustObservationNoticeState();
}

class _TrustObservationNoticeState extends State<TrustObservationNotice> {
  Future<void>? _pending;
  bool _failed = false;

  Future<void> _open() {
    if (!mounted || widget.caller.status != TrustObservationStatus.denied) {
      return Future<void>.value();
    }
    final pending = _pending;
    if (pending != null) return pending;
    final done = Completer<void>();
    _pending = done.future;
    final action = widget.openSettings;
    setState(() => _failed = false);
    scheduleMicrotask(() async {
      if (mounted && widget.caller.status == TrustObservationStatus.denied) {
        try {
          await action();
        } catch (_) {
          if (mounted) _failed = true;
        }
      }
      _pending = null;
      if (mounted) setState(() {});
      done.complete();
    });
    return done.future;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.caller,
    builder: (context, _) {
      if (widget.caller.status == TrustObservationStatus.granted) {
        return const SizedBox.shrink();
      }
      final denied = widget.caller.status == TrustObservationStatus.denied;
      final text = switch (widget.caller.status) {
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text),
            if (denied && _pending != null)
              Text(
                Strings.t(
                  'Opening Accessibility settings. Permission is not verified.',
                  'פותח את הגדרות הנגישות. ההרשאה לא אומתה.',
                ),
              ),
            if (denied && _failed)
              Text(
                Strings.t(
                  'Could not open Accessibility settings. Try again explicitly.',
                  'לא ניתן לפתוח את הגדרות הנגישות. אפשר לנסות שוב.',
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: widget.caller.loading
                ? null
                : () => unawaited(widget.caller.check()),
            child: Text(
              widget.caller.loading
                  ? Strings.t('Checking...', 'בודק...')
                  : Strings.t('Check status', 'בדיקת מצב'),
            ),
          ),
          if (denied)
            TextButton(
              onPressed: _pending != null ? null : () => unawaited(_open()),
              child: Text(
                _pending != null
                    ? Strings.t('Opening...', 'פותח...')
                    : _failed
                    ? Strings.t(
                        'Retry opening settings',
                        'ניסיון חוזר לפתיחת הגדרות',
                      )
                    : Strings.t('Open settings', 'פתיחת הגדרות'),
              ),
            ),
        ],
      );
    },
  );
}
