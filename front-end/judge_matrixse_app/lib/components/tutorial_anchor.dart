import 'package:flutter/material.dart';

import '../service/tutorial/tutorial_steps.dart';

class TutorialAnchors {
  TutorialAnchors._();

  static final _keys = <TutorialTarget, GlobalKey>{};

  static GlobalKey keyFor(TutorialTarget target) {
    return _keys.putIfAbsent(target, GlobalKey.new);
  }

  static Rect? rectFor(TutorialTarget target) {
    final context = _keys[target]?.currentContext;
    if (context == null) return null;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;

    final offset = box.localToGlobal(Offset.zero);
    return offset & box.size;
  }
}

class TutorialAnchor extends StatelessWidget {
  const TutorialAnchor({
    super.key,
    required this.target,
    required this.child,
  });

  final TutorialTarget target;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: TutorialAnchors.keyFor(target),
      child: child,
    );
  }
}
