import 'package:flutter/material.dart';

import '../services/screen_watch.dart';
import '../services/strings.dart';

/// Persistent in-app indicator shown on every screen while a watch session
/// runs (#212): red dot, countdown, one-tap stop. Sits above the Navigator
/// via the app builder, so no route can hide it.
class WatchBanner extends StatelessWidget {
  const WatchBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ScreenWatch.instance,
      builder: (context, _) {
        final active = ScreenWatch.instance.isActive;
        final dark = Theme.of(context).brightness == Brightness.dark;
        final background = dark
            ? const Color(0xFF5F1414)
            : const Color(0xFFFFEAEA);
        final foreground = dark
            ? const Color(0xFFFFEAEA)
            : const Color(0xFF5F1414);
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
                          label: Strings.t(
                            'Screen watching is active',
                            'צפייה במסך פעילה',
                          ),
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
                                    Strings.t(
                                      'Watching ${_mmss(ScreenWatch.instance.remaining)}',
                                      'צופה ${_mmss(ScreenWatch.instance.remaining)}',
                                    ),
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
                          label: Strings.t(
                            'Stop screen watching',
                            'עצירת צפייה במסך',
                          ),
                          button: true,
                          onTap: ScreenWatch.instance.stop,
                          child: ExcludeSemantics(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                foregroundColor: foreground,
                              ),
                              onPressed: ScreenWatch.instance.stop,
                              child: Text(Strings.t('Stop', 'עצירה')),
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
