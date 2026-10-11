import 'package:flutter/material.dart';

/// Scrolls independent notices without replacing or covering the route body.
class MacNoticeRegion extends StatelessWidget {
  const MacNoticeRegion({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.45,
    ),
    child: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}
