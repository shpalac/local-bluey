import 'package:flutter/material.dart';

import '../services/tutorial.dart';

/// Floating first-success tutorial card (#176): one instruction at a time,
/// each completed by doing the real gesture, skippable at every step.
class TutorialCard extends StatelessWidget {
  const TutorialCard({super.key, required this.controller});

  final TutorialController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.visible) return const SizedBox.shrink();
        final steps = controller.steps;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'First steps',
                      style: Theme.of(context).textTheme.titleSmall,
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
                Row(
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
                              steps.indexOf(s) < steps.indexOf(controller.step)
                              ? Colors.green
                              : null,
                        ),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: controller.skip,
                      child: const Text('Skip tutorial'),
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
