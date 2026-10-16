import 'package:flutter/material.dart';

import '../services/screen_watch.dart';
import '../services/capture_monitor.dart';
import '../teach_mode/capture_session.dart';
import '../services/strings.dart';

/// Persistent in-app indicator shown on every screen while a watch session
/// runs (#212): red dot, countdown, one-tap stop. Sits above the Navigator
/// via the app builder, so no route can hide it.
class WatchBanner extends StatelessWidget {
  const WatchBanner({
    super.key,
    required this.child,
    this.watch,
    this.teachSession,
  });

  final Widget child;
  final ScreenWatch? watch;
  final TeachCaptureSession? teachSession;

  @override
  Widget build(BuildContext context) {
    final currentWatch = watch ?? ScreenWatch.instance;
    final teaching = teachSession ?? TeachCaptureSession.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([currentWatch, teaching]),
      builder: (context, _) {
        final active = currentWatch.isActive;
        final isTeaching = teaching.indicator != CaptureIndicator.off;
        final isPaused = teaching.indicator == CaptureIndicator.paused;
        final stop = isTeaching ? teaching.cancel : currentWatch.stop;
        final bannerLabel = isTeaching
            ? isPaused
                  ? Strings.t('Teach Mode paused', 'מצב לימוד מושהה')
                  : Strings.t('Teach Mode active', 'מצב לימוד פעיל')
            : Strings.t('Screen watching is active', 'צפייה במסך פעילה');
        final actionLabel = isTeaching
            ? Strings.t('Cancel Teach Mode', 'ביטול מצב לימוד')
            : Strings.t('Stop screen watching', 'עצירת צפייה במסך');
        final visualLabel = isTeaching
            ? isPaused
                  ? Strings.t('Teach Mode paused', 'מצב לימוד מושהה')
                  : Strings.t('Teach Mode active', 'מצב לימוד פעיל')
            : Strings.t(
                'Watching ${_mmss(currentWatch.remaining)}',
                'צופה ${_mmss(currentWatch.remaining)}',
              );
        final dark = Theme.of(context).brightness == Brightness.dark;
        final background = isPaused
            ? (dark ? const Color(0xFF5F4214) : const Color(0xFFFFF1D8))
            : (dark ? const Color(0xFF5F1414) : const Color(0xFFFFEAEA));
        final foreground = isPaused
            ? (dark ? const Color(0xFFFFF1D8) : const Color(0xFF5F4214))
            : (dark ? const Color(0xFFFFEAEA) : const Color(0xFF5F1414));
        // Paint/traverse the route first so Navigator semantics cannot hide the
        // persistent control. Reverse layout reserves the banner above the route.
        return Column(
          verticalDirection: VerticalDirection.up,
          children: [
            Expanded(child: child),
            if (active)
              SafeArea(
                bottom: false,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Semantics(
                          container: true,
                          label: bannerLabel,
                          child: ExcludeSemantics(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fiber_manual_record,
                                  size: 12,
                                  color: foreground,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    visualLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(color: foreground),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Semantics(
                          container: true,
                          label: actionLabel,
                          button: true,
                          onTap: stop,
                          child: ExcludeSemantics(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                foregroundColor: foreground,
                              ),
                              onPressed: stop,
                              child: Text(
                                isTeaching
                                    ? Strings.t('Cancel', 'ביטול')
                                    : Strings.t('Stop', 'עצירה'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static String _mmss(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
