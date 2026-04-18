import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../theme/moodiary_colors.dart';
import '../widgets/glass.dart';

class InAppNotifications {
  InAppNotifications._();

  static final InAppNotifications instance = InAppNotifications._();

  GlobalKey<NavigatorState>? _navigatorKey;
  final Queue<_NotificationPayload> _queue = Queue<_NotificationPayload>();
  OverlayEntry? _entry;

  void configure(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
  }

  void show({
    required String title,
    required String message,
    IconData icon = Icons.notifications,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (_navigatorKey == null) return;
    _queue.add(
      _NotificationPayload(
        title: title,
        message: message,
        icon: icon,
        duration: duration,
      ),
    );
    _displayNext();
  }

  void _displayNext() {
    if (_entry != null || _queue.isEmpty) return;
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) return;
    final payload = _queue.removeFirst();

    _entry = OverlayEntry(
      builder: (context) =>
          _InAppBanner(payload: payload, onDismissed: _handleDismissed),
    );

    overlay.insert(_entry!);
  }

  void _handleDismissed() {
    _entry?.remove();
    _entry = null;
    if (_queue.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 150), _displayNext);
    }
  }
}

class _NotificationPayload {
  final String title;
  final String message;
  final IconData icon;
  final Duration duration;

  _NotificationPayload({
    required this.title,
    required this.message,
    required this.icon,
    required this.duration,
  });
}

class _InAppBanner extends StatefulWidget {
  final _NotificationPayload payload;
  final VoidCallback onDismissed;

  const _InAppBanner({required this.payload, required this.onDismissed});

  @override
  State<_InAppBanner> createState() => _InAppBannerState();
}

class _InAppBannerState extends State<_InAppBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..forward();
    _dismissTimer = Timer(widget.payload.duration, _close);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    if (!_controller.isAnimating) {
      _controller.reverse().then((value) {
        if (mounted) widget.onDismissed();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = media.padding.top + 16;

    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut)),
        child: GestureDetector(
          onTap: _close,
          child: Material(
            color: Colors.transparent,
            child: GlassContainer(
              blurSigma: context.mdGlassBlurMedium,
              borderRadius: BorderRadius.circular(18),
              backgroundColor: context.mdGlassSurfaceStrong,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Icon(widget.payload.icon, color: context.mdAccentPurple),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.payload.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: context.mdPrimaryText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.payload.message,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.mdSecondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _close,
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: context.mdSecondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
