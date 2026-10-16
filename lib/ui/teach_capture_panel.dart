import 'package:flutter/material.dart';

import '../services/capture_monitor.dart';
import '../services/screen_watch.dart';
import '../services/strings.dart';
import '../teach_mode/capture_session.dart';

/// User-owned Teach Mode session controls. The session itself owns the
/// observation gate, not this widget: navigating away never silently stops
/// the indicator or grants consent to any host action.
///
/// BLU-012 exposes the safe lifecycle only. Capturing actual user actions
/// requires a separate, approved event producer; do not imply that this
/// control records arbitrary keystrokes or screen contents.
class TeachCapturePanel extends StatefulWidget {
  const TeachCapturePanel({super.key, this.session, this.watch});

  /// Injectable for deterministic widget tests. Production uses the shared
  /// memory-only controller so the app-wide banner follows this session.
  final TeachCaptureSession? session;
  final ScreenWatch? watch;

  @override
  State<TeachCapturePanel> createState() => _TeachCapturePanelState();
}

class _TeachCapturePanelState extends State<TeachCapturePanel> {
  bool _requesting = false;

  TeachCaptureSession get _session =>
      widget.session ?? TeachCaptureSession.instance;

  ScreenWatch get _watch => widget.watch ?? ScreenWatch.instance;

  String _t(String en, String he) => Strings.t(en, he);

  Future<void> _confirmStart() async {
    if (_requesting || _watch.isActive) return;
    setState(() => _requesting = true);
    try {
      final scope = await _session.prepareConsent();
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_t('Start Teach Mode?', 'להתחיל מצב לימוד?')),
          content: Text(
            _t(
              'Allowlisted apps: ${scope.apps.join(', ')}.\n'
              'Session lasts at most 10 minutes. You can pause or cancel '
              'at any time. Sensitive or unknown apps stop observation.\n'
              'Only validated action identifiers can enter an in-memory '
              'draft; no screen content or typed values are saved. '
              'No actions are executed. Automatic capture of host actions '
              'is not yet connected.',
              'אפליקציות מורשות: ${scope.apps.join(', ')}.\n'
              'משך הסשן לכל היותר עשר דקות. ניתן לעצור או לבטל בכל רגע. '
              'אפליקציה רגישה או לא מוכרת עוצרת את התצפית.\n'
              'רק מזהי פעולות מאומתים נשמרים בזיכרון לטיוטה. '
              'לא נשמרים תוכן המסך או טקסט מוקלד, ולא מבוצעות פעולות. '
              'קליטת פעולות אוטומטית עדיין אינה מחוברת.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('Not now', 'לא עכשיו')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('I agree — start', 'אני מסכים — התחל')),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      final refusal = await _session.start(
        consentConfirmed: true,
        duration: scope.length,
        consent: scope,
      );
      if (mounted && refusal != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(refusal)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t('Teach Mode policy is unavailable.', 'מדיניות מצב לימוד אינה זמינה.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_session, _watch]),
      builder: (context, _) {
        final indicator = _session.indicator;
        final status = switch (indicator) {
          CaptureIndicator.off => _t('Teach Mode: off', 'מצב לימוד: כבוי'),
          CaptureIndicator.active => _t('Teach Mode: active', 'מצב לימוד: פעיל'),
          CaptureIndicator.paused => _t('Teach Mode: paused', 'מצב לימוד: מושהה'),
        };
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _t('Teach Mode (preview)', 'מצב לימוד (תצוגה מקדימה)'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    status,
                    key: const ValueKey('teach-capture-status'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _t(
                    'Session controls only. Automatic demonstration recording '
                    'is not enabled. Drafts cannot execute actions.',
                    'בקרת סשן בלבד. הקלטת הדגמה אוטומטית עדיין אינה פעילה. '
                    'טיוטות אינן יכולות לבצע פעולות.',
                  ),
                ),
                const SizedBox(height: 12),
                if (indicator == CaptureIndicator.off)
                  FilledButton.icon(
                    key: const ValueKey('teach-start'),
                    onPressed: _requesting || _watch.isActive
                        ? null
                        : _confirmStart,
                    icon: const Icon(Icons.school_outlined),
                    label: Text(_t('Start Teach Mode', 'התחל מצב לימוד')),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('teach-pause-resume'),
                        onPressed: indicator == CaptureIndicator.active
                            ? _session.pause
                            : _session.resume,
                        icon: Icon(
                          indicator == CaptureIndicator.active
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        label: Text(
                          indicator == CaptureIndicator.active
                              ? _t('Pause Teach Mode', 'השהה מצב לימוד')
                              : _t('Resume Teach Mode', 'המשך מצב לימוד'),
                        ),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('teach-cancel'),
                        onPressed: _session.cancel,
                        icon: const Icon(Icons.stop),
                        label: Text(_t('Cancel Teach Mode', 'בטל מצב לימוד')),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
