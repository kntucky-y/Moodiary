import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/moodiary_colors.dart';
import '../../widgets/glass.dart';
import '../auth/login_screen.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
const _kPurple = Color(0xFF9B7FDB);
const _kDark = Color(0xFF1A1A2E);
const _kGreen = Color(0xFF5DB87A);
const _kTeal = Color(0xFF44BBCC);
const _kYellow = Color(0xFFE8B84B);

// ─── Screen ───────────────────────────────────────────────────────────────────
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  void _next() {
    if (_page < 2) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  void _back() {
    _controller.previousPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final sideInset = width >= 700 ? 16.0 : 0.0;

    return Scaffold(
      backgroundColor: context.mdScaffold,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              context.mdScaffold,
              context.mdSecondarySurface.withValues(alpha: 0.38),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: sideInset),
          child: PageView(
            controller: _controller,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              _Page1(
                onNext: _next,
                dots: _Dots(current: _page),
              ),
              _Page2(
                onNext: _next,
                onBack: _back,
                dots: _Dots(current: _page),
              ),
              _Page3(
                onNext: _next,
                onBack: _back,
                dots: _Dots(current: _page),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Page 1 ───────────────────────────────────────────────────────────────────
class _Page1 extends StatelessWidget {
  final VoidCallback onNext;
  final Widget dots;
  const _Page1({required this.onNext, required this.dots});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;
    final sheetFraction = h < 720 ? 0.46 : 0.38;
    final iconSize = (w * 0.22).clamp(64.0, 92.0);

    return Stack(
      children: [
        // Upper content — 2×2 emoji grid with centred title
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: h * sheetFraction,
          child: Padding(
            padding: EdgeInsets.only(top: h * 0.06),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _FloatingImage(
                        'assets/sad.png',
                        size: iconSize,
                        delayFraction: 0,
                      ),
                      _FloatingImage(
                        'assets/confused.png',
                        size: iconSize,
                        delayFraction: 0.25,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Welcome to',
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFF666666),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const _MoodiaryLogo(),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _FloatingImage(
                        'assets/love.png',
                        size: iconSize,
                        delayFraction: 0.5,
                      ),
                      _FloatingImage(
                        'assets/angry.png',
                        size: iconSize,
                        delayFraction: 0.75,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Bottom sheet
        Align(
          alignment: Alignment.bottomCenter,
          child: _Sheet(
            height: h * sheetFraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),
                const Text(
                  "We're here to\ntrack your\nmood journey",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: _kDark,
                    height: 1.35,
                  ),
                ),
                const Spacer(),
                _PurpleButton(label: 'Next', onPressed: onNext),
                const SizedBox(height: 20),
                dots,
                SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Page 2 ───────────────────────────────────────────────────────────────────
class _Page2 extends StatelessWidget {
  final VoidCallback onNext, onBack;
  final Widget dots;
  const _Page2({
    required this.onNext,
    required this.onBack,
    required this.dots,
  });

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final sheetFraction = h < 760 ? 0.5 : 0.44;

    return Stack(
      children: [
        // Subtitle
        Positioned(
          top: 90,
          left: 28,
          right: 28,
          child: Text(
            'Start your journey towards self-awareness\nby tracking your mood effortlessly',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF444444),
              fontStyle: FontStyle.italic,
              height: 1.5,
            ),
          ),
        ),
        // 3×2 emoji grid
        Positioned(
          top: 150,
          left: 0,
          right: 0,
          bottom: h * sheetFraction,
          child: const _EmojiGrid(
            images: [
              'assets/star.png',
              'assets/neutral.png',
              'assets/bliss.png',
              'assets/cry.png',
              'assets/angry.png',
              'assets/kiss.png',
            ],
          ),
        ),
        // Bottom sheet
        Align(
          alignment: Alignment.bottomCenter,
          child: _Sheet(
            height: h * sheetFraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                    children: [
                      TextSpan(
                        text: 'T',
                        style: TextStyle(color: _kDark),
                      ),
                      TextSpan(
                        text: 'r',
                        style: TextStyle(color: _kPurple),
                      ),
                      TextSpan(
                        text: 'a',
                        style: TextStyle(color: _kGreen),
                      ),
                      TextSpan(
                        text: 'c',
                        style: TextStyle(color: _kTeal),
                      ),
                      TextSpan(
                        text: 'k',
                        style: TextStyle(color: _kDark),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'how you feel, every day',
                  style: TextStyle(fontSize: 16, color: _kDark),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tap on doodle moods, write your thoughts, and understand your emotional patterns.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF666666),
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
                ),
                const Spacer(),
                _PurpleButton(label: 'Next', onPressed: onNext),
                const SizedBox(height: 16),
                Center(child: dots),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
              ],
            ),
          ),
        ),
        // Back arrow (on top)
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios,
              color: Color(0xFF888888),
              size: 20,
            ),
            onPressed: onBack,
          ),
        ),
      ],
    );
  }
}

// ─── Page 3 ───────────────────────────────────────────────────────────────────
class _Page3 extends StatelessWidget {
  final VoidCallback onNext, onBack;
  final Widget dots;
  const _Page3({
    required this.onNext,
    required this.onBack,
    required this.dots,
  });

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final sheetFraction = h < 760 ? 0.54 : 0.47;

    return Stack(
      children: [
        // 3×2 character grid
        Positioned(
          top: 76,
          left: 0,
          right: 0,
          bottom: h * sheetFraction,
          child: const _EmojiGrid(
            images: [
              'assets/doodle1.png',
              'assets/doodle2.png',
              'assets/doodle3.png',
              'assets/doodle4.png',
              'assets/doodle5.png',
              'assets/doodle6.png',
            ],
          ),
        ),
        // Bottom sheet
        Align(
          alignment: Alignment.bottomCenter,
          child: _Sheet(
            height: h * sheetFraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 38, fontWeight: FontWeight.bold),
                    children: [
                      TextSpan(
                        text: 'G',
                        style: TextStyle(color: _kPurple),
                      ),
                      TextSpan(
                        text: 'a',
                        style: TextStyle(color: _kGreen),
                      ),
                      TextSpan(
                        text: 'i',
                        style: TextStyle(color: _kTeal),
                      ),
                      TextSpan(
                        text: 'n',
                        style: TextStyle(color: _kYellow),
                      ),
                    ],
                  ),
                ),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 38, fontWeight: FontWeight.bold),
                    children: [
                      TextSpan(
                        text: 'M',
                        style: TextStyle(color: _kDark),
                      ),
                      TextSpan(
                        text: 'e',
                        style: TextStyle(color: _kPurple),
                      ),
                      TextSpan(
                        text: 'n',
                        style: TextStyle(color: _kTeal),
                      ),
                      TextSpan(
                        text: 't',
                        style: TextStyle(color: _kGreen),
                      ),
                      TextSpan(
                        text: 'al ',
                        style: TextStyle(color: _kDark),
                      ),
                      TextSpan(
                        text: 'C',
                        style: TextStyle(color: _kPurple),
                      ),
                      TextSpan(
                        text: 'l',
                        style: TextStyle(color: _kGreen),
                      ),
                      TextSpan(
                        text: 'a',
                        style: TextStyle(color: _kTeal),
                      ),
                      TextSpan(
                        text: 'r',
                        style: TextStyle(color: _kDark),
                      ),
                      TextSpan(
                        text: 'i',
                        style: TextStyle(color: _kPurple),
                      ),
                      TextSpan(
                        text: 't',
                        style: TextStyle(color: _kYellow),
                      ),
                      TextSpan(
                        text: 'y',
                        style: TextStyle(color: _kGreen),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Visual insights and mood graphs help you see what affects your well-being. We also have companions to help you on your journey! Moodiary nudges you lovingly — like a note from your past self.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF666666),
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
                ),
                const Spacer(),
                _PurpleButton(label: 'Get Started', onPressed: onNext),
                const SizedBox(height: 16),
                Center(child: dots),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
              ],
            ),
          ),
        ),
        // Back arrow (on top)
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios,
              color: Color(0xFF888888),
              size: 20,
            ),
            onPressed: onBack,
          ),
        ),
      ],
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _MoodiaryLogo extends StatelessWidget {
  const _MoodiaryLogo();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'mo',
            style: GoogleFonts.lexend(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF374151),
            ),
          ),
          TextSpan(
            text: 'o',
            style: GoogleFonts.lexend(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF60A5FA),
            ),
          ),
          TextSpan(
            text: 'd',
            style: GoogleFonts.playfairDisplay(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF374151),
            ),
          ),
          TextSpan(
            text: 'i',
            style: GoogleFonts.caveat(
              fontSize: 58,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF4ADE80),
            ),
          ),
          TextSpan(
            text: 'a',
            style: GoogleFonts.playfairDisplay(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF374151),
            ),
          ),
          TextSpan(
            text: 'r',
            style: GoogleFonts.lexend(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: const Color(0xFFA076F9),
            ),
          ),
          TextSpan(
            text: 'y',
            style: GoogleFonts.caveat(
              fontSize: 58,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  final double height;
  final Widget child;
  const _Sheet({required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width >= 700 ? 36.0 : 28.0;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: GlassContainer(
        blurSigma: context.mdGlassBlurMedium,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        backgroundColor: context.mdGlassSurfaceStrong,
        borderColor: context.mdGlassBorder,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.mdInputBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurpleButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _PurpleButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          elevation: 0,
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int current;
  const _Dots({required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        3,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: i == current ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: i == current ? _kPurple : const Color(0xFFCCCCCC),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

class _EmojiGrid extends StatelessWidget {
  final List<String> images;
  const _EmojiGrid({required this.images});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final count = width >= 900
        ? 5
        : width >= 700
        ? 4
        : 3;

    return GridView.count(
      crossAxisCount: count,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: width >= 700 ? 28 : 24),
      children: images
          .map(
            (path) => Padding(
              padding: const EdgeInsets.all(8),
              child: _MoodImage(path),
            ),
          )
          .toList(),
    );
  }
}

class _FloatingImage extends StatefulWidget {
  final String path;
  final double size;
  final double delayFraction;
  const _FloatingImage(this.path, {this.size = 80, this.delayFraction = 0});

  @override
  State<_FloatingImage> createState() => _FloatingImageState();
}

class _FloatingImageState extends State<_FloatingImage>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final dy = -10 * sin((_ctrl.value + widget.delayFraction) * 2 * pi);
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
      child: Image.asset(
        widget.path,
        width: widget.size,
        height: widget.size,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.sentiment_satisfied_alt_rounded,
          size: widget.size,
          color: const Color(0xFFCCCCCC),
        ),
      ),
    );
  }
}

class _MoodImage extends StatelessWidget {
  final String path;
  const _MoodImage(this.path);

  @override
  Widget build(BuildContext context) {
    const double moodSize = 48;
    return Image.asset(
      path,
      width: moodSize,
      height: moodSize,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.sentiment_satisfied_alt_rounded,
        size: moodSize,
        color: const Color(0xFFCCCCCC),
      ),
    );
  }
}
