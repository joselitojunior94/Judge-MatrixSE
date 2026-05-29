import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'tutorial_anchor.dart';
import '../service/tutorial/tutorial_controller.dart';
import '../service/tutorial/tutorial_steps.dart';
import '../theme/app_theme.dart';

class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  final _controller = TutorialController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncScreen);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncScreen());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncScreen);
    super.dispose();
  }

  void _syncScreen() {
    if (!mounted || !_controller.active) return;
    widget.onNavigate(_controller.currentStep.screenIndex);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (!_controller.active) return const SizedBox.shrink();

        final media = MediaQuery.of(context);
        final size = media.size;
        final step = _controller.currentStep;
        final target = _targetRect(size, media.padding.top, step.target);
        final cardAlignment =
            size.width < 720
                ? Alignment.bottomCenter
                : _cardAlignment(step.target);

        return Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                CustomPaint(size: size, painter: _SpotlightPainter(target)),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  left: target.left,
                  top: target.top,
                  width: target.width,
                  height: target.height,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.cyan, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.cyan.withValues(alpha: .55),
                            blurRadius: 22,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: cardAlignment,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _CoachMarkCard(
                        step: step,
                        stepNumber: _controller.step + 1,
                        totalSteps: tutorialSteps.length,
                        isFirst: _controller.isFirstStep,
                        isLast: _controller.isLastStep,
                        onBack: _controller.previous,
                        onNext: _controller.next,
                        onSkip: _controller.skip,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Rect _targetRect(Size size, double topPadding, TutorialTarget target) {
    final anchored = TutorialAnchors.rectFor(target);
    if (anchored != null) {
      return _expandedAnchor(target, anchored, size);
    }

    final appTop = topPadding;
    final appBarHeight = 64.0;
    final phone = size.width < 720;
    final compactNav = size.width < 980;
    final navWidth = phone ? 0.0 : (compactNav ? 92.0 : 252.0);
    final bodyTop = topPadding + appBarHeight;
    final bodyHeight = size.height - bodyTop;
    final contentLeft = navWidth;
    final contentWidth = size.width - navWidth;
    final navItemHeight = 72.0;

    Rect mobileMenuTarget() => Rect.fromLTWH(8, appTop + 6, 48, 48);

    Rect navItem(int index) {
      if (phone) return mobileMenuTarget();
      final topOffset = compactNav ? 108.0 : 132.0;
      return Rect.fromLTWH(
        14,
        bodyTop + topOffset + (index * navItemHeight),
        navWidth - 26,
        compactNav ? 58 : 64,
      );
    }

    return switch (target) {
      TutorialTarget.appTitle => Rect.fromLTWH(
        phone ? 56 : 12,
        appTop + 8,
        phone ? 130 : 230,
        48,
      ),
      TutorialTarget.homeHero => Rect.fromLTWH(
        contentLeft + 24,
        bodyTop + 36,
        phone ? contentWidth - 48 : contentWidth * .58,
        bodyHeight * .34,
      ),
      TutorialTarget.datasetNav => navItem(1),
      TutorialTarget.datasetWizard => Rect.fromLTWH(
        contentLeft + 28,
        bodyTop + 28,
        contentWidth - 56,
        bodyHeight * .58,
      ),
      TutorialTarget.evaluationsNav => navItem(2),
      TutorialTarget.evaluationsToolbar => Rect.fromLTWH(
        contentLeft + 28,
        bodyTop + 100,
        240,
        56,
      ),
      TutorialTarget.evaluationActions => Rect.fromLTWH(
        phone ? 18 : size.width - 345,
        bodyTop + 165,
        phone ? size.width - 36 : 310,
        70,
      ),
      TutorialTarget.peopleNav => navItem(4),
      TutorialTarget.profileNav => navItem(5),
      TutorialTarget.rankingsNav => navItem(6),
      TutorialTarget.accountMenu => Rect.fromLTWH(
        phone ? size.width - 58 : size.width - 245,
        appTop + 8,
        phone ? 44 : 178,
        48,
      ),
    };
  }

  Rect _expandedAnchor(TutorialTarget target, Rect rect, Size size) {
    final inset = switch (target) {
      TutorialTarget.datasetNav ||
      TutorialTarget.evaluationsNav ||
      TutorialTarget.peopleNav ||
      TutorialTarget.profileNav ||
      TutorialTarget.rankingsNav => 6.0,
      TutorialTarget.evaluationsToolbar => 10.0,
      TutorialTarget.evaluationActions => 8.0,
      TutorialTarget.appTitle || TutorialTarget.accountMenu => 8.0,
      _ => 12.0,
    };
    final expanded = rect.inflate(inset);
    return Rect.fromLTRB(
      expanded.left.clamp(8.0, size.width - 16.0),
      expanded.top.clamp(8.0, size.height - 16.0),
      expanded.right.clamp(16.0, size.width - 8.0),
      expanded.bottom.clamp(16.0, size.height - 8.0),
    );
  }

  Alignment _cardAlignment(TutorialTarget target) {
    return switch (target) {
      TutorialTarget.appTitle ||
      TutorialTarget.accountMenu => Alignment.bottomCenter,
      TutorialTarget.datasetNav ||
      TutorialTarget.evaluationsNav ||
      TutorialTarget.peopleNav ||
      TutorialTarget.profileNav ||
      TutorialTarget.rankingsNav => Alignment.centerRight,
      TutorialTarget.evaluationActions => Alignment.centerLeft,
      _ => Alignment.bottomRight,
    };
  }
}

class _CoachMarkCard extends StatelessWidget {
  const _CoachMarkCard({
    required this.step,
    required this.stepNumber,
    required this.totalSteps,
    required this.isFirst,
    required this.isLast,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
  });

  final TutorialStep step;
  final int stepNumber;
  final int totalSteps;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .32),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: AppTheme.cyan.withValues(alpha: .10),
            blurRadius: 40,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.cyan.withValues(alpha: .16),
                  child: Icon(step.icon, size: 20, color: AppTheme.cyan),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Step $stepNumber of $totalSteps',
                    style: TextStyle(
                      color: AppTheme.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(onPressed: onSkip, child: const Text('Skip')),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              step.title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(step.body),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: stepNumber / totalSteps,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (!isFirst)
                  OutlinedButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: onNext,
                  icon: Icon(isLast ? Icons.check : Icons.arrow_forward),
                  label: Text(isLast ? 'Finish' : step.primaryLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.target);

  final Rect target;

  @override
  void paint(Canvas canvas, Size size) {
    final screenPath = Path()..addRect(Offset.zero & size);
    final spotlightPath =
        Path()..addRRect(
          RRect.fromRectAndRadius(target.inflate(6), const Radius.circular(16)),
        );
    final overlayPath = Path.combine(
      PathOperation.difference,
      screenPath,
      spotlightPath,
    );

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: .74),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(target.inflate(12), const Radius.circular(18)),
      Paint()
        ..shader = ui.Gradient.radial(target.center, target.longestSide, [
          AppTheme.cyan.withValues(alpha: .16),
          Colors.white.withValues(alpha: 0),
        ]),
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.target != target;
  }
}
