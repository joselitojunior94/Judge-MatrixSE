import 'package:flutter/material.dart';

import '../../pages/shared/page_container.dart';
import '../../service/tutorial/tutorial_controller.dart';

/// Tutorial landing page.
///
/// The actual tutorial is the Shell-level coach-mark overlay. This page exists
/// as the persistent restart point in the navigation rail.
class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key});

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!TutorialController.instance.active) {
        TutorialController.instance.start(restart: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageContainer(
      title: 'Tutorial',
      subtitle: 'Interactive guided tour',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.help_outline,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'The guided tutorial opens as a coach-mark overlay on top of the real workspace.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'It highlights actual controls, darkens the rest of the screen, and walks through the workflow step by step. You can skip it at any time.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () =>
                    TutorialController.instance.start(restart: true),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Restart guided tutorial'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
