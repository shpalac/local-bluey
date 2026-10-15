import 'package:flutter/material.dart';

import '../link/models.dart';
import '../services/strings.dart';
import 'bluey_character.dart';
import '../services/support_matrix.dart';

/// Shown when this platform has no supported role (#84): explains why and
/// what works today instead of rendering a broken client UI. Starts no
/// network, audio or discovery work.
class UnsupportedScreen extends StatelessWidget {
  const UnsupportedScreen({
    super.key,
    required this.profile,
    this.showMascot = true,
  });

  final PlatformProfile profile;

  /// Suppress only when replaying the original documentation golden.
  final bool showMascot;

  static const readmeMatrixUrl =
      'https://github.com/shpalac/local-bluey#platform-support';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showMascot)
                SizedBox(
                  height: 148,
                  width: 148,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: MediaQuery.of(context).disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 2400),
                    curve: Curves.easeInOut,
                    builder: (context, phase, _) => BlueyCharacter(
                      face: FaceState(mood: Mood.happy),
                      awake: true,
                      tint: const Color(0xFF5BC8E5),
                      phase: phase,
                    ),
                  ),
                )
              else
                Semantics(
                  label: Strings.t(
                    'Unsupported platform icon',
                    'סמל פלטפורמה לא נתמכת',
                  ),
                  child: const Icon(Icons.devices_other, size: 64),
                ),
              const SizedBox(height: 24),
              Text(
                Strings.t(
                  'Local Bluey does not support this platform yet',
                  'Local Bluey עוד לא תומך בפלטפורמה הזו',
                ),
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                SupportMatrix.unsupportedReason(profile),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                Strings.t(
                  'Supported today: macOS as the host, iPhone and Android as remotes.',
                  'נתמך היום: macOS כמארח, iPhone ואנדרויד כשלטים.',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SelectableText(
                readmeMatrixUrl,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
