import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/moodiary_colors.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final double blurSigma;
  final Color? backgroundColor;
  final Color? borderColor;
  final Gradient? gradient;
  final List<BoxShadow>? shadows;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.blurSigma = 14,
    this.backgroundColor,
    this.borderColor,
    this.gradient,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedRadius =
        borderRadius ?? BorderRadius.circular(context.mdRadiusLg);
    final baseColor = backgroundColor ?? context.mdGlassSurface;
    final baseBorder = borderColor ?? context.mdGlassBorder;
    final overlayTop = context.mdGlassHighlight.withValues(
      alpha: context.isDarkMode ? 0.18 : 0.26,
    );
    final overlayBottom = Colors.white.withValues(
      alpha: context.isDarkMode ? 0.03 : 0.10,
    );

    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: resolvedRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: baseColor,
              gradient: gradient,
              borderRadius: resolvedRadius,
              border: Border.all(color: baseBorder),
              boxShadow: shadows ?? context.mdGlassShadows,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: resolvedRadius,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            overlayTop,
                            Colors.transparent,
                            overlayBottom,
                          ],
                          stops: const [0.0, 0.56, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: padding ?? const EdgeInsets.all(16),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final double blurSigma;
  final Color? backgroundColor;
  final Color? borderColor;

  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.borderRadius,
    this.blurSigma = 14,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedRadius =
        borderRadius ?? BorderRadius.circular(context.mdRadiusLg);

    return GlassContainer(
      blurSigma: blurSigma,
      borderRadius: resolvedRadius,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: resolvedRadius,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}
