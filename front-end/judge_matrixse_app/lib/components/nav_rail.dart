import 'dart:ui';

import 'package:flutter/material.dart';

import '../service/tutorial/tutorial_steps.dart';
import '../theme/app_theme.dart';
import 'tutorial_anchor.dart';

class NavRail extends StatelessWidget {
  final int idx;
  final ValueChanged<int> onSelect;

  const NavRail({super.key, required this.idx, required this.onSelect});

  static const _items = <_NavItem>[
    _NavItem(
      label: 'Home',
      detail: 'Workspace overview',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      section: 'Studio',
      index: 0,
    ),
    _NavItem(
      label: 'Datasets',
      detail: 'Upload and map CSVs',
      icon: Icons.upload_file_outlined,
      selectedIcon: Icons.cloud_done_rounded,
      section: 'Workflow',
      index: 1,
      target: TutorialTarget.datasetNav,
    ),
    _NavItem(
      label: 'Evaluations',
      detail: 'Studies and roles',
      icon: Icons.fact_check_outlined,
      selectedIcon: Icons.fact_check_rounded,
      section: 'Workflow',
      index: 2,
      target: TutorialTarget.evaluationsNav,
    ),
    _NavItem(
      label: 'Public',
      detail: 'Join open studies',
      icon: Icons.travel_explore_outlined,
      selectedIcon: Icons.travel_explore_rounded,
      section: 'Workflow',
      index: 3,
    ),
    _NavItem(
      label: 'People',
      detail: 'Find collaborators',
      icon: Icons.groups_2_outlined,
      selectedIcon: Icons.groups_2_rounded,
      section: 'People',
      index: 4,
      target: TutorialTarget.peopleNav,
    ),
    _NavItem(
      label: 'Profile',
      detail: 'Your identity',
      icon: Icons.person_outline,
      selectedIcon: Icons.person_rounded,
      section: 'People',
      index: 5,
      target: TutorialTarget.profileNav,
    ),
    _NavItem(
      label: 'Rankings',
      detail: 'Points and activity',
      icon: Icons.emoji_events_outlined,
      selectedIcon: Icons.emoji_events_rounded,
      section: 'People',
      index: 6,
      target: TutorialTarget.rankingsNav,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 980;
    final width = compact ? 92.0 : 252.0;

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.surface.withValues(alpha: .70),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: .10)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .28),
                    blurRadius: 28,
                    offset: const Offset(0, 18),
                  ),
                  BoxShadow(
                    color: AppTheme.cyan.withValues(alpha: .05),
                    blurRadius: 36,
                  ),
                ],
              ),
              child: Column(
                children: [
                  _NavHeader(compact: compact),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 10 : 12,
                        8,
                        compact ? 10 : 12,
                        8,
                      ),
                      child: Column(children: _groupedItems(compact)),
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

  List<Widget> _groupedItems(bool compact) {
    final children = <Widget>[];
    String? currentSection;
    for (final item in _items) {
      if (item.section != currentSection) {
        currentSection = item.section;
        children.add(_SectionLabel(label: currentSection, compact: compact));
      }
      final button = _NavButton(
        item: item,
        selected: idx == item.index,
        compact: compact,
        onTap: () => onSelect(item.index),
      );
      children.add(
        item.target == null
            ? button
            : TutorialAnchor(target: item.target!, child: button),
      );
      children.add(SizedBox(height: compact ? 5 : 7));
    }
    return children;
  }
}

class _NavHeader extends StatelessWidget {
  const _NavHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 10 : 14, 14, compact ? 10 : 14, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 9 : 12),
          child: Row(
            mainAxisAlignment:
                compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.cyan.withValues(alpha: .95),
                      AppTheme.indigo.withValues(alpha: .88),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.cyan.withValues(alpha: .25),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.hub_rounded,
                  color: Color(0xFF061019),
                  size: 21,
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Command',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Live study control',
                        style: TextStyle(
                          color: AppTheme.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.compact});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) return const SizedBox(height: 10);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 7),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: AppTheme.muted.withValues(alpha: .72),
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final compact = widget.compact;
    final activeColor = selected ? AppTheme.cyan : AppTheme.muted;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:
          (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? .985 : (_hovered ? 1.018 : 1),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 210),
            curve: Curves.easeOutCubic,
            constraints: BoxConstraints(minHeight: compact ? 56 : 62),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 9 : 10,
            ),
            decoration: BoxDecoration(
              color:
                  selected
                      ? AppTheme.cyan.withValues(alpha: .13)
                      : _hovered
                      ? Colors.white.withValues(alpha: .065)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    selected
                        ? AppTheme.cyan.withValues(alpha: .36)
                        : Colors.white.withValues(alpha: _hovered ? .10 : 0),
              ),
              boxShadow:
                  selected
                      ? [
                        BoxShadow(
                          color: AppTheme.cyan.withValues(alpha: .13),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ]
                      : null,
            ),
            child: Row(
              mainAxisAlignment:
                  compact ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 210),
                  curve: Curves.easeOutCubic,
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color:
                        selected
                            ? AppTheme.cyan.withValues(alpha: .18)
                            : Colors.white.withValues(alpha: .055),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    selected ? widget.item.selectedIcon : widget.item.icon,
                    color: activeColor,
                    size: 21,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? AppTheme.text : AppTheme.muted,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.item.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.muted.withValues(alpha: .78),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 210),
                    width: selected ? 7 : 0,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.cyan,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.detail,
    required this.icon,
    required this.selectedIcon,
    required this.section,
    required this.index,
    this.target,
  });

  final String label;
  final String detail;
  final IconData icon;
  final IconData selectedIcon;
  final String section;
  final int index;
  final TutorialTarget? target;
}
