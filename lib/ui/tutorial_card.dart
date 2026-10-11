import 'package:flutter/material.dart';

import '../services/tutorial.dart';
import '../services/strings.dart';

/// Floating first-success tutorial card (#176): one instruction at a time,
/// each completed by doing the real gesture, skippable at every step.
class TutorialCard extends StatefulWidget {
  const TutorialCard({super.key, required this.controller});

  final TutorialController controller;

  @override
  State<TutorialCard> createState() => _TutorialCardState();
}

class _TutorialCardState extends State<TutorialCard> {
  bool _pending = false;
  int _attempt = 0;

  TutorialController get controller => widget.controller;

  @override
  void didUpdateWidget(TutorialCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, controller)) {
      ++_attempt;
      _pending = false;
    }
  }

  Future<void> _skip() async {
    if (_pending) return;
    final owner = controller;
    final attempt = ++_attempt;
    setState(() => _pending = true);
    try {
      await owner.skip();
    } catch (_) {
      // The owner exposes a safe current storageError. Never show raw errors.
    } finally {
      if (mounted && attempt == _attempt && identical(owner, controller)) {
        setState(() => _pending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.visible) return const SizedBox.shrink();
        final steps = controller.steps;
        final failed = controller.storageError != null;
        final hebrew = Strings.forceRtl;
        final pendingText = hebrew ? 'שומר...' : 'Saving...';
        final errorText = hebrew
            ? 'לא ניתן לשמור את השלמת ההדרכה. נסה שוב.'
            : 'Could not save tutorial completion. Try again.';
        final retryText = hebrew ? 'נסה שוב' : 'Retry';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'First steps',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${steps.indexOf(controller.step) + 1}/${steps.length}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(controller.instruction),
                const SizedBox(height: 8),
                if (failed) ...[
                  Text(
                    errorText,
                    key: const ValueKey('tutorial-storage-error'),
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final s in steps)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              steps.indexOf(s) < steps.indexOf(controller.step)
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              size: 14,
                              color:
                                  steps.indexOf(s) <
                                      steps.indexOf(controller.step)
                                  ? Colors.green
                                  : null,
                            ),
                          ),
                      ],
                    ),
                    TextButton(
                      key: const ValueKey('tutorial-complete'),
                      onPressed: _pending ? null : _skip,
                      child: Text(
                        _pending
                            ? pendingText
                            : failed
                            ? retryText
                            : 'Skip tutorial',
                      ),
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
