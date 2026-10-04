import 'package:flutter/widgets.dart';

/// Animation duration that respects the system reduce-motion setting (#88):
/// transitions become instant, but state stays visible.
Duration motionDuration(BuildContext context, {int ms = 250}) =>
    MediaQuery.of(context).disableAnimations
    ? Duration.zero
    : Duration(milliseconds: ms);
