import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool interactive;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.interactive = true,
  });

  @override
  Widget build(BuildContext context) {
    return _HoverLift(
      enabled: interactive,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.elevated.withValues(alpha: .62),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: .10)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .28),
                  blurRadius: 26,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: AppTheme.cyan.withValues(alpha: .04),
                  blurRadius: 28,
                ),
              ],
            ),
            child:
                padding == null
                    ? child
                    : Padding(padding: padding!, child: child),
          ),
        ),
      ),
    );
  }
}

class _HoverLift extends StatefulWidget {
  const _HoverLift({required this.child, required this.enabled});

  final Widget child;
  final bool enabled;

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.012 : 1,
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutBack,
        child: AnimatedSlide(
          offset: _hovered ? const Offset(0, -.006) : Offset.zero,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}
