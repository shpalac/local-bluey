import 'package:flutter/material.dart';

import '../services/watch_suggestions.dart';

/// Quiet, read-only suggestion card (#214): shows why the watcher spoke
/// up and the on-screen evidence behind it. Two exits - dismiss, or
/// "never for this app". It does nothing else; that is the point.
class WatchSuggestionCard extends StatelessWidget {
  const WatchSuggestionCard({
    super.key,
    required this.suggestion,
    required this.onDismiss,
    required this.onNeverForApp,
  });

  final WatchSuggestion suggestion;
  final VoidCallback onDismiss;
  final VoidCallback onNeverForApp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: ListTile(
        leading: Icon(Icons.visibility_outlined, color: scheme.primary),
        title: Text(suggestion.reason),
        subtitle: Text(suggestion.evidence),
        trailing: Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: onNeverForApp,
              child: Text('Never for ${suggestion.app}'),
            ),
            TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
          ],
        ),
      ),
    );
  }
}
