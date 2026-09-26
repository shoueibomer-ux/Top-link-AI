import 'package:flutter/material.dart';

import '../app_colors.dart';

/// The Top-Link AI logo: the circular "TLA" roundel, on its own.
///
/// Deliberately never paired with the "Top-Link AI" wordmark or tagline text,
/// at any screen size — the circle stands alone (see assets/images/
/// toplinkai_icon.png). An earlier version peeked a wordmark out beside the
/// icon on a timer; that's been removed entirely rather than merely hidden on
/// phones, so no screen can render the text next to the circle.
///
/// The roundel sits on a light pill backdrop so its navy disc keeps its edge
/// against the navy app bar / drawer header (and reads the same on the light
/// paywall background).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 32});

  final double height;

  static const _pillPadding = EdgeInsets.all(4);
  static const _pillRadius = 12.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Top-Link AI',
      image: true,
      child: Container(
        padding: _pillPadding,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(_pillRadius),
        ),
        child: ExcludeSemantics(
          child: Image.asset('assets/images/toplinkai_icon.png', height: height, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
