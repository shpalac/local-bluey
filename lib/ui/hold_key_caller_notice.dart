import 'dart:async';

import 'package:flutter/material.dart';

import '../services/hold_key_caller.dart';

/// Independent lifecycle notice, never request or recording bubble state.
class HoldKeyCallerNotice extends StatelessWidget {
  const HoldKeyCallerNotice({super.key, required this.caller});
  final HoldKeyCaller caller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: caller,
    builder: (context, _) => !caller.failed
        ? const SizedBox.shrink()
        : MaterialBanner(
            content: const Text(
              'Could not update hold-key settings. Shortcut state is not verified.',
            ),
            actions: [
              TextButton(
                onPressed: caller.loading
                    ? null
                    : () => unawaited(caller.retry()),
                child: Text(caller.loading ? 'Retrying...' : 'Retry'),
              ),
            ],
          ),
  );
}
