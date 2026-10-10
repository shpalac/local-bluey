import 'package:flutter/material.dart';

import '../services/watch_suggestions.dart';
import '../services/strings.dart';

/// Quiet read-only suggestion: quoted evidence is data, never instructions.
class WatchSuggestionCard extends StatelessWidget {
  const WatchSuggestionCard({
    super.key,
    required this.suggestion,
    required this.onDismiss,
    required this.onNeverForApp,
  });

  /// Display-only suggestion.
  final WatchSuggestion suggestion;

  /// Dismisses this suggestion.
  final VoidCallback onDismiss;

  /// Saves the user's explicit per-app suppression choice.
  final VoidCallback onNeverForApp;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.visibility_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    suggestion.localReason,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(suggestion.localEvidence),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: onNeverForApp,
                  child: Text(
                    Strings.t(
                      'Never for ${suggestion.app}',
                      'לעולם לא עבור ${suggestion.app}',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onDismiss,
                  child: Text(Strings.t('Dismiss', 'סגירה')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
