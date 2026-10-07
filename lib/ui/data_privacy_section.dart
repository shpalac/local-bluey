import 'package:flutter/material.dart';

import '../services/data_registry.dart';
import '../services/strings.dart';

/// Settings > Data and privacy (#83): every registered store with its
/// retention and a clear button, plus a guarded delete-all that returns the
/// app to first-run state.
class DataPrivacySection extends StatefulWidget {
  const DataPrivacySection({super.key, this.onCleared, this.onBusyChanged});

  /// Notify the owning form after successful deletion, never on failure.
  final Future<void> Function(String? storeId)? onCleared;

  /// Prevent saves while deletion or its form reset is in progress.
  final void Function(bool busy)? onBusyChanged;

  @override
  State<DataPrivacySection> createState() => _DataPrivacySectionState();
}

class _DataPrivacySectionState extends State<DataPrivacySection> {
  bool _busy = false;

  Future<void> _clearStore(DataStoreInfo store) async {
    setState(() => _busy = true);
    widget.onBusyChanged?.call(true);
    try {
      await store.clear();
      await widget.onCleared?.call(store.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Strings.t('${store.id} cleared', '${store.id} נוקה')),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete local data: $error')),
        );
      }
    } finally {
      widget.onBusyChanged?.call(false);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          Strings.t('Delete all local data?', 'למחוק את כל הנתונים המקומיים?'),
        ),
        content: Text(
          Strings.t(
            'This wipes every store listed here, the API key and pairing keys, and returns the app to first-run state. Your remote provider account data is not touched.',
            'פעולה זו מוחקת את כל המאגרים הרשומים כאן, את מפתח ה-API ומפתחות ההתאמה, ומחזירה את האפליקציה למצב ראשוני. נתוני חשבון הספק המרוחק לא נגעים.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(Strings.t('Cancel', 'ביטול')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(Strings.t('Delete everything', 'מחק הכל')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    widget.onBusyChanged?.call(true);
    try {
      await DataRegistry.deleteAll();
      await widget.onCleared?.call(null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Strings.t('All local data deleted', 'כל הנתונים המקומיים נמחקו'),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete local data: $error')),
        );
      }
    } finally {
      widget.onBusyChanged?.call(false);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          Strings.t('Data and privacy', 'נתונים ופרטיות'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          Strings.t(
            'Everything the app keeps on this device, where, and for how long.',
            'כל מה שהאפליקציה שומרת על המכשיר, איפה, ולכמה זמן.',
          ),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final store in DataRegistry.stores)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(Strings.t(store.whatEn, store.whatHe)),
            subtitle: Text(
              '${store.where} · ${Strings.t(store.retentionEn, store.retentionHe)}',
            ),
            trailing: IconButton(
              tooltip: Strings.t('Clear', 'נקה'),
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : () => _clearStore(store),
            ),
          ),
        const SizedBox(height: 12),
        Semantics(
          button: true,
          label: Strings.t(
            'Delete all local data',
            'מחק את כל הנתונים המקומיים',
          ),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: _busy ? null : _deleteAll,
            icon: const Icon(Icons.delete_forever),
            label: Text(
              Strings.t('Delete all local data', 'מחק את כל הנתונים המקומיים'),
            ),
          ),
        ),
      ],
    );
  }
}
