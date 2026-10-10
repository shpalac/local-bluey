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
        return Stack(
          children: [
            child,
            if (active)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
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
                                    color: Theme.of(context).colorScheme.error,
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
                                          .labelLarge,
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
                                  foregroundColor: Theme.of(context)
                                      .colorScheme
                                      .error,
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
