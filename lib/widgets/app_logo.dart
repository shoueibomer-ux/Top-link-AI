import 'package:flutter/material.dart';

import '../app_colors.dart';

/// "tabmatch": lowercase, "tab" in white (navy on a light background) and
/// "match" in turquoise. Live text, so it stays sharp at any size and follows
/// the system font scale.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.fontSize = 22, this.onLight = false});

  final double fontSize;

  /// True on a light background, where "tab" is navy instead of white.
  final bool onLight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Tabmatch',
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'tab', style: TextStyle(color: onLight ? AppColors.navy : AppColors.white)),
              const TextSpan(text: 'match', style: TextStyle(color: AppColors.turquoise)),
            ],
          ),
          key: const Key('wordmark'),
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.1),
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }
}

/// The Tabmatch logo: the "tm" mark with the wordmark beside it.
///
/// The mark is a navy rounded tile, so on the navy app bar and drawer header
/// only the white T and turquoise m show; pass [onLight] on a light background,
/// where the tile and a navy "tab" stand out instead. [showWordmark] false
/// gives just the mark, for tight spots.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 32, this.onLight = false, this.showWordmark = true});

  final double height;
  final bool onLight;
  final bool showWordmark;

  static const markAsset = 'assets/brand/tabmatch_icon_192.png';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Tabmatch',
      image: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(markAsset, height: height, width: height, filterQuality: FilterQuality.medium),
            if (showWordmark) ...[
              SizedBox(width: height * 0.28),
              // Shrinks to fit rather than overflowing (large system text sizes, narrow drawers).
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Wordmark(fontSize: height * 0.72, onLight: onLight),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
