import 'package:flutter/material.dart';

import '../services/screen_watch.dart';
import '../services/strings.dart';
import '../services/watch_policy.dart';

/// Screen watching: consent, allowlist, explainer and session controls
/// (#212). Everything on this screen is localized EN/HE and follows the
/// app-level Directionality for RTL.
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  List<String> _allowlist = [];
  Duration _length = ScreenWatch.defaultSessionLength;
  final _appField = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final apps = await WatchPolicy.allowlist();
    if (mounted) setState(() => _allowlist = apps);
  }

  String _t(String en, String he) => Strings.t(en, he);

  Future<void> _start() async {
    final minutes = _length.inMinutes;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Watch your screen?', 'לצפות במסך?')),
        content: Text(
          _t(
            'For the next $minutes minutes Bluey will look at your screen.\n\n'
                '- Only apps on your allowlist are observed.\n'
                '- Password managers, banking, private windows, System Settings '
                'and the lock screen are never observed.\n'
                '- Everything stays on this Mac (local-only).\n'
                '- Nothing is stored when the session ends.\n\n'
                'You can stop at any time with one tap.',
            'במשך $minutes הדקות הבאות Bluey יסתכל על המסך שלך.\n\n'
                '- רק אפליקציות ברשימה שלך נצפות.\n'
                '- מנהלי סיסמאות, בנקים, חלונות פרטיים, הגדרות המערכת '
                'ומסך הנעילה לעולם לא נצפים.\n'
                '- הכל נשאר על המק הזה (מקומי בלבד).\n'
                '- שום דבר לא נשמר כשהסשן מסתיים.\n\n'
                'אפשר לעצור בכל רגע בלחיצה אחת.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_t('Not now', 'לא עכשיו')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_t('Start watching', 'התחל צפייה')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final refusal = await ScreenWatch.instance.start(
      length: _length,
      consentConfirmed: true,
    );
    if (!mounted) return;
    if (refusal != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(refusal)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_t('Screen watching', 'צפייה במסך'))),
      body: ListenableBuilder(
        listenable: ScreenWatch.instance,
        builder: (context, _) {
          final watch = ScreenWatch.instance;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('What is watched', 'מה נצפה'),
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        _t(
                          'Only the apps on your allowlist, only during a '
                              'session you start yourself.',
                          'רק אפליקציות ברשימה שלך, רק במהלך סשן '
                              'שהתחלת בעצמך.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _t('What is stored', 'מה נשמר'),
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        _t(
                          'Nothing. Observations live for the session and '
                              'vanish when it ends. The only record is a count '
                              'of times an excluded app was in front.',
                          'כלום. התצפיות חיות במהלך הסשן ונעלמות כשהוא '
                              'מסתיים. הרישום היחיד הוא ספירת הפעמים שאפליקציה '
                              'מוחרגת הייתה בחזית.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _t('How to delete it', 'איך מוחקים'),
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        _t(
                          'There is nothing to delete - stopping a session '
                              'discards it. The exclusion count can be reset '
                              'below.',
                          'אין מה למחוק - עצירת סשן משליכה אותו. '
                              'את ספירת ההחרגות אפשר לאפס למטה.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _t('Allowed apps', 'אפליקציות מורשות'),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final app in _allowlist)
                ListTile(
                  dense: true,
                  title: Text(app),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () async {
                      await WatchPolicy.removeFromAllowlist(app);
                      await _reload();
                    },
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _appField,
                      decoration: InputDecoration(
                        hintText: _t(
                          'App name, e.g. Safari',
                          'שם אפליקציה, למשל Safari',
                        ),
                      ),
                      onSubmitted: (_) => _addApp(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _addApp,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _t('Session length', 'אורך סשן'),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final option in ScreenWatch.sessionOptions)
                    ChoiceChip(
                      label: Text(
                        _t(
                          '${option.inMinutes} min',
                          '${option.inMinutes} דקות',
                        ),
                      ),
                      selected: _length == option,
                      onSelected: (_) => setState(() => _length = option),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (!watch.isActive)
                FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(_t('Start a session', 'התחלת סשן')),
                )
              else ...[
                Text(
                  _t(
                    'Watching - ${_mmss(watch.remaining)} left',
                    'צופה - נותרו ${_mmss(watch.remaining)}',
                  ),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                  ),
                  onPressed: watch.stop,
                  icon: const Icon(Icons.stop),
                  label: Text(_t('Stop now', 'עצירה עכשיו')),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _t(
                        'Excluded moments: ${watch.excludedCount}',
                        'רגעים מוחרגים: ${watch.excludedCount}',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: watch.resetExcludedCount,
                    child: Text(_t('Reset', 'איפוס')),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addApp() async {
    final app = _appField.text;
    if (app.trim().isEmpty) return;
    await WatchPolicy.addToAllowlist(app);
    _appField.clear();
    await _reload();
  }

  static String _mmss(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _appField.dispose();
    super.dispose();
  }
}
