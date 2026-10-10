import 'package:flutter/material.dart';

import '../services/hold_key.dart';
import '../services/hold_key_controller.dart';
import '../services/strings.dart';

/// Settings for the global hold-to-talk key (#228). Off by default; the host
/// follows [HoldKeySettings] and starts the listener when it is switched on.
class HoldKeySection extends StatefulWidget {
  /// Creates the section.
  const HoldKeySection({super.key});

  @override
  State<HoldKeySection> createState() => _HoldKeySectionState();
}

class _HoldKeySectionState extends State<HoldKeySection> {
  bool _busy = false;
  bool _failed = false;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    var failed = false;
    try {
      await action();
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = failed;
    });
  }

  static String _label(HoldKey key) => switch (key) {
    HoldKey.rightCommand => Strings.t('Right Command', 'Command ימני'),
    HoldKey.leftCommand => Strings.t('Left Command', 'Command שמאלי'),
    HoldKey.rightOption => Strings.t('Right Option', 'Option ימני'),
    HoldKey.fn => Strings.t('Fn / Globe', 'Fn / גלובוס'),
    HoldKey.other => '',
  };

  @override
  Widget build(BuildContext context) {
    final settings = HoldKeySettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        children: [
          if (_failed)
            const ListTile(
              title: Text(
                'Could not update hold-key preferences. Check current values and try again.',
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.keyboard),
            title: Text(Strings.t('Hold a key to talk', 'החזקת מקש לדיבור')),
            subtitle: Text(
              !settings.verified
                  ? 'Hold-key preferences could not be verified. Previous settings are retained.'
                  : settings.permissionMissing
                  ? Strings.t(
                      'macOS has not allowed Input Monitoring. Allow Local '
                          'Bluey in System Settings, Privacy & Security, '
                          'Input Monitoring, then switch this on again.',
                      'מערכת ההפעלה לא אישרה ניטור קלט. אפשרו ל-Local Bluey '
                          'בהגדרות מערכת, פרטיות ואבטחה, ניטור קלט, ואז הפעילו '
                          'שוב.',
                    )
                  : Strings.t(
                      'Hold the key alone from any app to talk, release to '
                          'send, Esc to cancel. Needs Input Monitoring.',
                      'החזיקו את המקש לבדו מכל אפליקציה כדי לדבר, שחררו '
                          'לשליחה, Esc לביטול. דורש ניטור קלט.',
                    ),
            ),
            value: settings.enabled,
            onChanged: _busy
                ? null
                : (value) => _run(() => settings.setEnabled(value)),
          ),
          if (settings.enabled)
            ListTile(
              title: Text(Strings.t('Key', 'מקש')),
              trailing: DropdownButton<HoldKey>(
                value: settings.key,
                items: [
                  for (final key in HoldKeySettings.choices)
                    DropdownMenuItem(value: key, child: Text(_label(key))),
                ],
                onChanged: _busy
                    ? null
                    : (key) {
                        if (key != null) _run(() => settings.setKey(key));
                      },
              ),
            ),
          if (settings.enabled)
            ListTile(
              title: Text(Strings.t('Hold for', 'משך החזקה')),
              trailing: DropdownButton<int>(
                value: settings.thresholdMs,
                items: [
                  for (final ms in HoldKeySettings.thresholds)
                    DropdownMenuItem(value: ms, child: Text('$ms ms')),
                ],
                onChanged: _busy
                    ? null
                    : (ms) {
                        if (ms != null) _run(() => settings.setThresholdMs(ms));
                      },
              ),
            ),
        ],
      ),
    );
  }
}
