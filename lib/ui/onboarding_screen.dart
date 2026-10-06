import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/first_success.dart';
import '../services/native_control.dart';
import '../services/onboarding_checks.dart';
import '../services/strings.dart';

String _t(String en, String he) => Strings.t(en, he);

/// First-run permission walkthrough, one permission per step (#174):
/// plain-language why, a verify button that re-checks the real grant, and
/// a deep link to the right System Settings pane. Progress persists per
/// step, so a returning user lands on the first unfinished step. The app
/// re-checks grants on resume; revocations surface as a recovery card in
/// the main window (PermissionWatchdog + PermissionRecoveryCard).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onDone,
    this.checker = const LivePermissionChecker(),
    this.readiness = checkServices,
    this.onPlan,
    this.onOpenSettings,
  });

  final VoidCallback onDone;
  final PermissionChecker checker;

  /// Verifies the brain endpoint and speech-to-text for the summary (#226).
  final Future<(ServiceReadiness, ServiceReadiness)> Function() readiness;

  /// Receives the first-success plan right before [onDone], so the tutorial
  /// can match what is actually ready.
  final ValueChanged<FirstSuccessPlan>? onPlan;

  /// Opens the app Settings (endpoint assistant) from a readiness fix.
  final VoidCallback? onOpenSettings;

  static const _kDone = 'onboarding.done';
  static const _kStepPrefix = 'onboarding.step.';
  static const _kDeferredPrefix = 'onboarding.deferred.';

  /// Permission ids the user chose to set up later (#224). Kept apart from
  /// the step-reviewed flag so navigation progress never reads as a grant.
  static Future<Set<String>> deferredSteps() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final p in onboardingPermissions)
        if (prefs.getBool('$_kDeferredPrefix${p.id}') ?? false) p.id,
    };
  }

  static Future<void> _setDeferred(String id, bool deferred) async =>
      (await SharedPreferences.getInstance()).setBool(
        '$_kDeferredPrefix$id',
        deferred,
      );

  static Future<bool> isDone() async =>
      (await SharedPreferences.getInstance()).getBool(_kDone) ?? false;

  static Future<void> markDone() async =>
      (await SharedPreferences.getInstance()).setBool(_kDone, true);

  static Future<void> _markStepDone(String id, bool done) async =>
      (await SharedPreferences.getInstance()).setBool('$_kStepPrefix$id', done);

  /// First step without a persisted completion, or the last step when every
  /// one is done (a returning user reviews the final step, not a blank end).
  static Future<int> firstUnfinishedStep() async {
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < onboardingPermissions.length; i++) {
      if (!(prefs.getBool('$_kStepPrefix${onboardingPermissions[i].id}') ??
          false)) {
        return i;
      }
    }
    return onboardingPermissions.length - 1;
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  /// Permissions with no OS preflight: their state is unknown, never denied.
  static const _notCheckable = {'local_network'};

  final _granted = <String, bool?>{};
  final _failed = <String, String>{};
  Set<String> _deferred = {};
  bool _summary = false;
  FirstSuccessPlan? _plan;
  int _step = 0;
  bool _busy = false;
  bool _disposed = false;

  /// Bumped on every step change and disposal. A verify result that finds a
  /// different generation than it started with is stale and dropped.
  int _gen = 0;

  /// Bumped on each refresh and disposal; only the newest refresh applies.
  int _refreshGen = 0;

  OnboardingPermission get _current => onboardingPermissions[_step];
  bool get _last => _step == onboardingPermissions.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OnboardingScreen.firstUnfinishedStep().then((step) {
      if (mounted) {
        _gen++;
        setState(() => _step = step);
      }
    });
    OnboardingScreen.deferredSteps().then((d) {
      if (mounted) setState(() => _deferred = d);
    });
    _refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    _refreshGen++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from system Settings re-checks everything (#86).
    if (state == AppLifecycleState.resumed) _refresh();
  }

  /// One check by permission id. Returns null when the state cannot be
  /// known (no preflight) and throws when the native check fails.
  Future<bool?> _check(String id) {
    final c = widget.checker;
    return switch (id) {
      'accessibility' => c.accessibility(),
      'screen_recording' => c.screenRecording(),
      'microphone' => c.microphone(),
      _ => Future<bool?>.value(null),
    };
  }

  Future<void> _refresh() async {
    final gen = ++_refreshGen;
    // Each permission is checked on its own so one failing native call
    // cannot hide the others' results.
    final statuses = <String, bool?>{};
    final errors = <String, String>{};
    for (final p in onboardingPermissions) {
      if (_notCheckable.contains(p.id)) {
        statuses[p.id] = null;
        continue;
      }
      try {
        statuses[p.id] = await _check(p.id);
      } catch (e) {
        errors[p.id] = '$e';
      }
    }
    if (_disposed || !mounted || gen != _refreshGen) return;
    setState(() {
      _granted.addAll(statuses);
      for (final id in statuses.keys) {
        _failed.remove(id);
      }
      _failed.addAll(errors);
    });
  }

  /// Re-checks the current permission alone. A grant only updates the
  /// status; the user moves on with Continue. Overlapping calls are ignored,
  /// and a result that arrives after Back/Later is discarded.
  Future<void> _verify() async {
    if (_busy) return;
    final id = _current.id;
    final gen = ++_gen;
    setState(() => _busy = true);
    bool? granted;
    String? error;
    try {
      granted = await _check(id);
    } catch (e) {
      error = '$e';
    }
    if (_disposed || !mounted) return;
    if (gen != _gen) {
      // The user moved on while the check ran; it must not touch this step.
      setState(() => _busy = false);
      return;
    }
    setState(() {
      _busy = false;
      if (error != null) {
        _failed[id] = error;
      } else {
        _failed.remove(id);
        _granted[id] = granted;
      }
    });
    if (error == null && granted == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              '${_current.localTitle} is still off - open Settings, grant it, '
                  'then check again.',
              '${_current.localTitle} עדיין כבוי - פתח הגדרות, אשר, '
                  'ואז בדוק שוב.',
            ),
          ),
        ),
      );
    }
  }

  /// Moves past the current step. [deferred] records a "set up later"
  /// choice; a granted step clears any earlier deferral.
  Future<void> _next({required bool deferred}) async {
    if (_busy) return;
    final id = _current.id;
    await OnboardingScreen._markStepDone(id, true);
    await OnboardingScreen._setDeferred(id, deferred);
    if (_disposed || !mounted) return;
    setState(() {
      deferred ? _deferred.add(id) : _deferred.remove(id);
    });
    if (_last) {
      _openSummary();
    } else {
      _gen++;
      setState(() => _step++);
    }
  }

  void _back() {
    if (_busy) return;
    _gen++;
    setState(() => _step--);
  }

  void _jumpTo(int step) {
    if (_busy || step == _step) return;
    _gen++;
    setState(() => _step = step);
  }

  Future<void> _openSettings() async {
    final id = _current.id;
    String? error;
    try {
      final result = await NativeControl.openURL(_current.settingsUrl);
      if (result == null || !result.startsWith('Opened')) {
        error = result ?? 'no response';
      }
    } catch (e) {
      error = '$e';
    }
    if (_disposed || !mounted) return;
    setState(() {
      if (error != null) {
        _failed['$id.settings'] = error;
      } else {
        _failed.remove('$id.settings');
      }
    });
  }

  /// Leaving early opens the summary; nothing is marked done until the
  /// user confirms there with the consequences in view.
  void _finishLater() {
    if (_busy) return;
    _openSummary();
  }

  /// Shows the summary and verifies what the first request depends on. The
  /// plan stays null while checking, so nothing claims readiness early.
  Future<void> _openSummary() async {
    _gen++;
    setState(() {
      _summary = true;
      _plan = null;
    });
    await _refresh();
    (ServiceReadiness, ServiceReadiness) services;
    try {
      services = await widget.readiness();
    } catch (_) {
      services = (ServiceReadiness.unreachable, ServiceReadiness.notConfigured);
    }
    if (_disposed || !mounted || !_summary) return;
    setState(() {
      _plan = FirstSuccessPlan.from(
        FirstSuccessInputs(
          accessibility: _granted['accessibility'] ?? false,
          screenRecording: _granted['screen_recording'] ?? false,
          microphone: _granted['microphone'] ?? false,
          brain: services.$1,
          stt: services.$2,
        ),
      );
    });
  }

  Future<void> _startBluey() async {
    final plan = _plan;
    if (_busy || plan == null) return;
    widget.onPlan?.call(plan);
    await OnboardingScreen.markDone();
    widget.onDone();
  }

  /// The visible status word for [p]; never colour or an icon alone (#227).
  String _statusWord(OnboardingPermission p) {
    if (_failed.containsKey(p.id)) {
      return _t('Unable to check', 'לא ניתן לבדוק');
    }
    if (_notCheckable.contains(p.id)) {
      return _t('Asked at pairing', 'תתבקש בחיבור');
    }
    return switch (_granted[p.id]) {
      true => _t('Granted', 'ניתנה'),
      false => _t('Not enabled', 'לא מופעלת'),
      null => _t('Checking...', 'בודק...'),
    };
  }

  String _stateLine(OnboardingPermission p) {
    if (_failed.containsKey(p.id)) {
      final help = _t(
        'Could not check this permission. Try again, or open '
            'System Settings > Privacy & Security and look for ${p.title}.',
        'לא ניתן לבדוק את ההרשאה הזו. נסה שוב, או פתח את הגדרות המערכת > '
            'פרטיות ואבטחה וחפש את ${p.localTitle}.',
      );
      return '${_statusWord(p)}. $help';
    }
    if (_notCheckable.contains(p.id)) {
      return _t(
        'macOS only asks for this when your iPhone first looks for '
            'this Mac, so it cannot be checked here. Skip it now and approve '
            'the prompt when you pair the phone.',
        'macOS מבקשת הרשאה זו רק כשה-iPhone שלך מחפש את ה-Mac הזה בפעם '
            'הראשונה, ולכן אי אפשר לבדוק אותה כאן. דלג עכשיו ואשר את '
            'ההודעה כשתצמיד את הטלפון.',
      );
    }
    return _statusWord(p);
  }

  /// What stays off when a permission is not granted (#224).
  static const _consequence = <String, (String, String)>{
    'accessibility': (
      'Bluey cannot click or type for you.',
      'בלואי לא יכול ללחוץ או להקליד בשבילך.',
    ),
    'screen_recording': (
      'Bluey cannot see what is on your screen.',
      'בלואי לא יכול לראות מה על המסך שלך.',
    ),
    'microphone': (
      'Bluey cannot hear you, so spoken questions will not work.',
      'בלואי לא יכול לשמוע אותך, ולכן שאלות בקול לא יעבדו.',
    ),
    'local_network': (
      'Your iPhone cannot find this Mac until you approve it.',
      'ה-iPhone שלך לא ימצא את ה-Mac הזה עד שתאשר.',
    ),
  };

  static const _laterLabel = <String, (String, String)>{
    'accessibility': (
      'Set up click control later',
      'הגדר שליטה בלחיצות מאוחר יותר',
    ),
    'screen_recording': (
      'Set up screen access later',
      'הגדר גישה למסך מאוחר יותר',
    ),
    'local_network': (
      'Set up phone pairing later',
      'הגדר חיבור לטלפון מאוחר יותר',
    ),
  };

  /// One display state per step: granted, deferred, unknown or missing.
  String _stateOf(OnboardingPermission p) {
    if (_granted[p.id] == true) return 'granted';
    if (_deferred.contains(p.id)) return 'deferred';
    if (_notCheckable.contains(p.id)) return 'unknown';
    return 'missing';
  }

  Widget _overview(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (var i = 0; i < onboardingPermissions.length; i++)
          ChoiceChip(
            key: Key('step-${onboardingPermissions[i].id}'),
            selected: i == _step,
            avatar: Icon(switch (_stateOf(onboardingPermissions[i])) {
              'granted' => Icons.check_circle,
              'deferred' => Icons.schedule,
              'unknown' => Icons.help_outline,
              _ => Icons.radio_button_unchecked,
            }, size: 18),
            label: Text(
              '${onboardingPermissions[i].localTitle} - '
              '${switch (_stateOf(onboardingPermissions[i])) {
                'granted' => _t('granted', 'ניתנה'),
                'deferred' => _t('later', 'מאוחר יותר'),
                'unknown' => _t('asked at pairing', 'תתבקש בחיבור'),
                _ => _t('not granted', 'לא ניתנה'),
              }}',
            ),
            onSelected: (_) => _jumpTo(i),
          ),
      ],
    );
  }

  /// First-success guidance from the verified plan (#226).
  Widget _firstRequest(BuildContext context) {
    final plan = _plan;
    if (plan == null) {
      return ListTile(
        key: Key('first-request'),
        leading: Icon(Icons.hourglass_top),
        title: Text(
          _t(
            'Checking your chat model and speech setup...',
            'בודק את מודל הצ\'אט ואת הגדרות הדיבור...',
          ),
        ),
      );
    }
    if (!plan.voiceReady) {
      return Column(
        key: const Key('first-request'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(Icons.warning_amber),
            title: Text(
              _t(
                'Not ready for a spoken question yet',
                'עדיין לא מוכן לשאלה בקול',
              ),
            ),
          ),
          for (final issue in plan.issues)
            ListTile(
              key: Key('issue-${issue.id}'),
              dense: true,
              title: Text(issue.message),
              trailing:
                  issue.id != 'microphone' && widget.onOpenSettings != null
                  ? TextButton(
                      onPressed: widget.onOpenSettings,
                      child: Text(_t('Open Settings', 'פתח הגדרות')),
                    )
                  : null,
            ),
        ],
      );
    }
    return Column(
      key: const Key('first-request'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.record_voice_over),
          title: Text(
            _t(
              'Try this first: hold the face and ask',
              'נסה קודם: החזק את הפנים ושאל',
            ),
          ),
          subtitle: Text('"${plan.suggestedRequest}"'),
        ),
        if (!plan.pointingAvailable)
          ListTile(
            key: Key('no-pointing'),
            dense: true,
            title: Text(
              _t(
                'Pointing needs Accessibility and Screen Recording, so the '
                    'tutorial will skip it for now.',
                'הצבעה דורשת נגישות והקלטת מסך, ולכן המדריך ידלג עליה '
                    'בינתיים.',
              ),
            ),
          ),
      ],
    );
  }

  Widget _summaryView(BuildContext context) {
    final rows = <Widget>[];
    for (final p in onboardingPermissions) {
      final state = _stateOf(p);
      rows.add(
        ListTile(
          key: Key('summary-${p.id}'),
          leading: Icon(
            state == 'granted' ? Icons.check_circle : Icons.info_outline,
          ),
          title: Text(p.localTitle),
          subtitle: Text(
            state == 'granted'
                ? _t('Available.', 'זמין.')
                : _t(_consequence[p.id]!.$1, _consequence[p.id]!.$2),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_t('Setup summary', 'סיכום ההגדרה'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(
                'You can change any of these later in System Settings. '
                    'Bluey tells you when a missing permission blocks something.',
                'אפשר לשנות כל אחת מההרשאות האלה אחר כך בהגדרות המערכת. '
                    'בלואי יגיד לך כשהרשאה חסרה חוסמת משהו.',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(children: [...rows, _firstRequest(context)]),
            ),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _gen++;
                          setState(() => _summary = false);
                        },
                  child: Text(_t('Back to setup', 'חזרה להגדרה')),
                ),
                FilledButton(
                  onPressed: _busy || _plan == null ? null : _startBluey,
                  child: Text(
                    _plan == null
                        ? _t('Checking...', 'בודק...')
                        : _t('Start Bluey', 'התחל עם בלואי'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_summary) return _summaryView(context);
    final p = _current;
    final granted = _granted[p.id];
    final failed = _failed.containsKey(p.id);
    final notCheckable = _notCheckable.contains(p.id);
    // One primary action per state.
    final Widget primary;
    if (granted == true || notCheckable) {
      primary = FilledButton(
        onPressed: _busy ? null : () => _next(deferred: notCheckable),
        child: Text(
          _last
              ? _t('Continue to summary', 'המשך לסיכום')
              : _t('Continue', 'המשך'),
        ),
      );
    } else if (granted == null && !failed) {
      primary = FilledButton(
        onPressed: null,
        child: Text(_t('Checking...', 'בודק...')),
      );
    } else {
      primary = FilledButton(
        onPressed: _openSettings,
        child: Text(_t('Open Settings', 'פתח הגדרות')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('Welcome to Local Bluey', 'ברוכים הבאים ל-Local Bluey')),
      ),
      // One focused panel: centred, width-bounded, scrolls when it cannot
      // fit (compact windows, large text) instead of overflowing (#223).
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _t('Set up ${p.title}', 'הגדרת ${p.localTitle}'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                _overview(context),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    title: Text(p.localTitle),
                    subtitle: Text(p.localWhy),
                    leading: failed
                        ? const Icon(Icons.error_outline)
                        : notCheckable
                        ? const Icon(Icons.help_outline)
                        : switch (granted) {
                            true => const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            ),
                            false => const Icon(Icons.radio_button_off),
                            null => const Icon(Icons.hourglass_top),
                          },
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  label: '${p.localTitle}: ${_statusWord(p)}',
                  child: ExcludeSemantics(
                    child: Text(
                      _stateLine(p),
                      key: const Key('onboarding-state'),
                    ),
                  ),
                ),
                if (_failed.containsKey('${p.id}.settings'))
                  Text(
                    _t(
                      'Could not open System Settings. Open it yourself: '
                          'Privacy & Security, then pick this permission.',
                      'לא ניתן לפתוח את הגדרות המערכת. פתח אותן בעצמך: '
                          'פרטיות ואבטחה, ואז בחר את ההרשאה.',
                    ),
                    key: Key('onboarding-settings-error'),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    primary,
                    if (!notCheckable && granted != true)
                      OutlinedButton(
                        onPressed: _busy ? null : _verify,
                        child: Text(_t('Check again', 'בדוק שוב')),
                      ),
                    if (!p.requiredForFirstAnswer &&
                        granted != true &&
                        !notCheckable)
                      TextButton(
                        onPressed: _busy ? null : () => _next(deferred: true),
                        child: Text(
                          _laterLabel[p.id] == null
                              ? _t('Set up later', 'הגדר מאוחר יותר')
                              : _t(
                                  _laterLabel[p.id]!.$1,
                                  _laterLabel[p.id]!.$2,
                                ),
                        ),
                      ),
                    if (_step > 0)
                      TextButton(
                        onPressed: _busy ? null : _back,
                        child: Text(_t('Back', 'חזרה')),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: _busy ? null : _finishLater,
                  child: Text(
                    _t('Finish setup later', 'סיים את ההגדרה מאוחר יותר'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
