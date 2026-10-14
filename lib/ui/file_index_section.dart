import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/file_index.dart';
import '../services/strings.dart';

/// macOS-only opt-in file index controls. Never scans without a chooser and
/// separate user confirmation. Revocation destroys every in-memory entry.
class FileIndexSection extends StatefulWidget {
  const FileIndexSection({super.key});

  @visibleForTesting
  static Future<String?> Function()? debugChooseDirectory;

  @override
  State<FileIndexSection> createState() => _FileIndexSectionState();
}

class _FileIndexSectionState extends State<FileIndexSection> {
  static const _channel = MethodChannel('local_bluey/file_index');
  final FileIndex _index = FileIndex.instance;
  bool _busy = false;
  String? _error;

  Future<void> _choose() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path =
          await (FileIndexSection.debugChooseDirectory?.call() ??
              _channel.invokeMethod<String>('chooseDirectory'));
      if (!mounted || path == null) {
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            Strings.t('Index selected folder?', 'לאנדקס את התיקייה שנבחרה?'),
          ),
          content: Text(
            Strings.t(
              'Local file contents will be scanned into memory. Hidden files are skipped. You can revoke access at any time; no content is uploaded.',
              'תוכן הקבצים המקומיים ייסרק לזיכרון. קבצים מוסתרים יוחרגו. ניתן לבטל גישה בכל עת; לא מתבצעת העלאה.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(Strings.t('Cancel', 'ביטול')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(Strings.t('Index folder', 'אנדקס תיקייה')),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) {
        return;
      }
      await _index.grant(Directory(path), consent: true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = Strings.t(
            'Cannot access the selected folder. Nothing was uploaded.',
            'אין גישה לתיקייה שנבחרה. לא הועלה שום מידע.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refresh() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _index.refresh();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = Strings.t(
            'Index refresh failed. Revoke to clear the index.',
            'עדכון האינדקס נכשל. ניתן לבטל כדי למחוק את האינדקס.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _revoke() {
    _index.revoke();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Strings.t('Local file indexing', 'אינדוקס קבצים מקומי'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(
          Strings.t(
            'Off by default. Indexed contents stay in memory until revoked or restart.',
            'כבוי כברירת מחדל. התוכן נשמר בזיכרון עד לביטול או להפעלה מחדש.',
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!, key: const Key('file-index-error')),
        Text(
          Strings.t(
            'Indexed files: ${_index.documentCount}',
            'קבצים באינדקס: ${_index.documentCount}',
          ),
          key: const Key('file-index-count'),
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : _choose,
              child: Text(Strings.t('Choose folder', 'בחירת תיקייה')),
            ),
            if (_index.isEnabled)
              OutlinedButton(
                onPressed: _busy ? null : _refresh,
                child: Text(Strings.t('Refresh', 'רענון')),
              ),
            if (_index.isEnabled)
              OutlinedButton(
                onPressed: _revoke,
                child: Text(Strings.t('Revoke and purge', 'ביטול ומחיקה')),
              ),
          ],
        ),
      ],
    );
  }
}
