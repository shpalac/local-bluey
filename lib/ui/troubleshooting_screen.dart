import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/diagnostics.dart';
import '../services/strings.dart';

/// Troubleshooting page with live checks and copyable diagnostics (#85).
class TroubleshootingScreen extends StatefulWidget {
  const TroubleshootingScreen({super.key});

  @override
  State<TroubleshootingScreen> createState() => _TroubleshootingState();
}

class _TroubleshootingState extends State<TroubleshootingScreen> {
  List<CheckResult>? _results;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final results = await Diagnostics.run();
    if (mounted) setState(() => _results = results);
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: AppBar(title: Text(Strings.t('Troubleshooting', 'פתרון בעיות'))),
      body: results == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final r in results)
                  ListTile(
                    leading: Icon(
                      switch (r.status) {
                        CheckStatus.pass => Icons.check_circle,
                        CheckStatus.fail => Icons.error,
                        CheckStatus.unknown => Icons.help,
                      },
                      color: switch (r.status) {
                        CheckStatus.pass => Colors.green,
                        CheckStatus.fail => Colors.red,
                        CheckStatus.unknown => Colors.grey,
                      },
                    ),
                    title: Text(Strings.t(r.titleEn, r.titleHe)),
                    subtitle: r.status == CheckStatus.fail && r.fixEn != null
                        ? Text(Strings.t(r.fixEn!, r.fixHe ?? r.fixEn!))
                        : null,
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    final report = Diagnostics.buildReport(
                      platform: Platform.operatingSystem,
                      role: 'app',
                      results: results,
                    );
                    Clipboard.setData(ClipboardData(text: report));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          Strings.t('Diagnostics copied', 'האבחון הועתק'),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: Text(Strings.t('Copy diagnostics', 'העתק אבחון')),
                ),
              ],
            ),
    );
  }
}
