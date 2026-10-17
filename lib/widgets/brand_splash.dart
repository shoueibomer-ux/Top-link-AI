import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_colors.dart';

/// What the app shows while it starts or waits on its first answer: the TM logo
/// alone, centered on navy, with a gentle pulse. No wordmark.
///
/// It is built to be indistinguishable from the native launch screen it follows
/// (flutter_native_splash, see pubspec.yaml): the same navy, the same image
/// ([markAsset], the logo on a 1152px canvas) drawn at the same 288 logical
/// pixels and centered, and it starts fully visible, so the hand-over from the
/// native screen to this one has no jump. It then pulses once, about a second:
/// the logo eases to a softer, slightly smaller state and back to full strength,
/// and rests there. It adds no delay of its own: it is on screen only while the
/// app is actually loading, and is replaced the moment loading ends. With the
/// system's "remove animations" setting on, it stays still.
class BrandSplash extends StatefulWidget {
  const BrandSplash({super.key});

  /// The same image the native splash is generated from.
  static const markAsset = 'assets/brand/tabmatch_splash_1152.png';

  /// The native splash draws that image at 288 dp; matching it keeps the logo the same size.
  static const markSize = 288.0;

  /// The one pulse, soft and back. The animation never runs longer than this.
  static const pulseDuration = Duration(milliseconds: 1000);

  /// The system bar the native splash shows: transparent, with light icons on the navy. Without
  /// this the status bar icons would flip to dark at the hand-over.
  static const systemBars = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light, // Android
    statusBarBrightness: Brightness.dark, // iOS
  );

  /// How faint and how small the logo gets at the softest point of the pulse.
  static const softestOpacity = 0.6;
  static const smallestScale = 0.96;

  /// Opacity and scale at [t], a position in the pulse from 0 to 1. At 0 (and 1)
  /// the logo is at full strength, exactly as the native splash draws it.
  static (double opacity, double scale) pulseAt(double t) {
    final strength =
        0.5 + 0.5 * math.cos(2 * math.pi * t); // 1 at the ends, 0 in the middle
    return (
      softestOpacity + (1 - softestOpacity) * strength,
      smallestScale + (1 - smallestScale) * strength,
    );
  }

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: BrandSplash.pulseDuration,
  );

  bool _reduceMotion = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _controller.stop();
      _controller.value = 0; // full strength, still
    } else if (!_started) {
      _started = true;
      _controller.forward(); // once: it rests at full strength when done
    }
    _reduceMotion = reduce;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      BrandSplash.markAsset,
      width: BrandSplash.markSize,
      height: BrandSplash.markSize,
      filterQuality: FilterQuality.medium,
      // The asset is part of the app; if it ever failed to load, show nothing rather than an error box.
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: BrandSplash.systemBars,
      child: Semantics(
        label: 'Tabmatch is loading',
        child: Scaffold(
          key: const Key('brand-splash'),
          backgroundColor: AppColors.navy,
          body: Center(
            child: _reduceMotion
                ? mark
                : AnimatedBuilder(
                    animation: _controller,
                    child: mark,
                    builder: (context, child) {
                      final (opacity, scale) = BrandSplash.pulseAt(
                        _controller.value,
                      );
                      return Opacity(
                        opacity: opacity,
                        child: Transform.scale(scale: scale, child: child),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
