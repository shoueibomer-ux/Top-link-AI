import 'dart:async';

import 'package:flutter/material.dart';

import '../app_colors.dart';

/// The full Top Link AI logo (icon + wordmark). The icon sits on a light
/// pill backdrop (for contrast against the navy app bar / drawer header);
/// the wordmark, when it peeks out, is drawn with no background of its own —
/// directly over whatever's behind it.
///
/// Default state is compact — just the circular "TA" icon. Periodically
/// (starting shortly after mount, then every ~8s) it peeks: the wordmark
/// reveals beside the icon with a fixed gap, holds briefly, then retracts
/// back to the compact icon-only state.
///
/// Icon and wordmark are two separate assets (toplinkai_icon.png /
/// toplinkai_wordmark.png, both cropped from the original combined
/// toplinkai_logo_full.png) laid out as sibling Row children — not, as in an
/// earlier version, two overlapping crops of one shared image. That
/// combined-image approach made the icon-to-text gap a fixed, tiny sliver
/// baked into the source PNG (~26px of 656) with no room to add real
/// spacing, and any width-reveal of the text necessarily read as sliding out
/// from under the icon rather than appearing beside it. Separate assets in a
/// Row give real control over the gap and let each element be sized/aligned
/// independently.
///
/// The wordmark is recolored via [wordmarkColor] (the source PNG bakes it in
/// a dark navy that's unreadable against a dark background) while the icon
/// keeps its own true colors — see the ColorFiltered layer in build().
/// Defaults to white for this app's three navy-background usages (the
/// AppBar title — home_screen.dart / onboarding_screen.dart, both navy via
/// the app's AppBarTheme — and the drawer header); the fourth usage
/// (paywall_screen.dart) sits on a light body background and passes
/// AppColors.navy instead. Recoloring alone wasn't enough to fix legibility:
/// toplinkai_wordmark.png's glyphs (especially the "AI-Powered Service
/// Matching" tagline) were baked with partial alpha (measured ~55-70% for
/// the title, as low as ~50% at its most solid rows for the tagline) —
/// BlendMode.srcIn replaces color but keeps the source alpha, so recoloring
/// alone still rendered as faded. The asset's alpha channel was boosted (3x,
/// clamped) so the glyphs reach full opacity while their antialiased edges
/// stay proportionally faint.
class AppLogo extends StatefulWidget {
  const AppLogo({super.key, this.height = 32, this.wordmarkColor = AppColors.white});

  final double height;

  // Must contrast with whatever this widget is placed on — see the class
  // doc above for why this isn't just always white.
  final Color wordmarkColor;

  @override
  State<AppLogo> createState() => _AppLogoState();
}

class _AppLogoState extends State<AppLogo> with SingleTickerProviderStateMixin {
  static const _pillPadding = EdgeInsets.symmetric(horizontal: 5, vertical: 4);

  // Fixed, not proportional to widget.height — the request was for
  // consistent spacing between the two call sites (AppBar height 32,
  // drawer header height 40), which a fixed gap gives directly.
  static const _wordmarkGap = 10.0;

  // The original combined asset's own ratio (icon 141px tall, wordmark
  // 47px tall out of the same 656x175 canvas, ~0.33) rendered the wordmark
  // too small to read at the header's actual on-screen size — bumped up
  // for legibility rather than preserved verbatim.
  static const _wordmarkHeightRatio = 0.6;

  late final AnimationController _controller;
  late final Animation<double> _reveal; // 0 = compact icon, 1 = full wordmark

  // A plain Timer (not Future.delayed) so it can be explicitly cancelled in
  // dispose() — Future.delayed leaves an uncancellable pending timer that
  // trips flutter_test's "timer still pending after dispose" check.
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _reveal = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _timer = Timer(const Duration(milliseconds: 700), _peek);
  }

  void _peek() {
    if (!mounted) return;
    _controller.forward();
    _timer = Timer(const Duration(milliseconds: 1800), _retract);
  }

  void _retract() {
    if (!mounted) return;
    _controller.reverse();
    _timer = Timer(const Duration(seconds: 6), _peek);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const iconAsset = 'assets/images/toplinkai_icon.png';
    const wordmarkAsset = 'assets/images/toplinkai_wordmark.png';
    final wordmarkHeight = widget.height * _wordmarkHeightRatio;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Icon — fixed white pill backdrop, always fully visible and never
        // affected by the wordmark's reveal (a separate, preceding Row
        // slot, not an underlying layer text can slide over or crowd).
        Container(
          padding: _pillPadding,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Image.asset(iconAsset, height: widget.height, fit: BoxFit.contain),
        ),
        // Wordmark reveal — the visible width of this (gap + wordmark) slot
        // grows from 0 to its natural width as `_reveal` animates, so the
        // gap and text appear together as one clean, evenly-spaced lockup
        // beside the icon.
        AnimatedBuilder(
          animation: _reveal,
          builder: (context, child) => ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              // widthFactor (not a SizedBox) so the child still lays out at
              // its natural size and only gets paint-clipped.
              widthFactor: _reveal.value,
              child: child,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: _wordmarkGap),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(widget.wordmarkColor, BlendMode.srcIn),
              child: Image.asset(wordmarkAsset, height: wordmarkHeight, fit: BoxFit.contain),
            ),
          ),
        ),
      ],
    );
  }
}
