import 'package:flutter/material.dart';
import 'package:judge_matrixse_app/components/glass_card.dart';
import 'package:judge_matrixse_app/components/gradient_background.dart';
import 'package:judge_matrixse_app/components/chip_comp.dart';
import 'package:judge_matrixse_app/theme/app_theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.onGetStarted,
    required this.onSeeEvals,
  });
  final VoidCallback onGetStarted;
  final VoidCallback onSeeEvals;

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > 1000;
              final hero = GlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.auto_awesome, color: AppTheme.cyan),
                        SizedBox(width: 8),
                        Text(
                          'Research-grade labeling cockpit',
                          style: TextStyle(
                            color: AppTheme.cyan,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Orchestrate human assessments with clarity.',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineMedium?.copyWith(height: 1.05),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Upload CSVs, define mappings, follow collaborators, assign judges and reviewers, inspect agreement, export results, and run AI meta-evaluation without letting AI cast human labels.',
                      style: TextStyle(color: AppTheme.muted, height: 1.45),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: const [
                        ChipComp(
                          icon: Icons.cloud_upload,
                          label: 'Upload & mapping',
                        ),
                        ChipComp(icon: Icons.rule, label: 'Judgment & review'),
                        ChipComp(
                          icon: Icons.analytics_outlined,
                          label: 'Automatic metrics',
                        ),
                        ChipComp(
                          icon: Icons.download_outlined,
                          label: 'Export CSV/JSON',
                        ),
                      ],
                    ),
                  ],
                ),
              );

              final cta = GlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next action',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Choose the workflow you need right now.',
                      style: TextStyle(color: AppTheme.muted),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: onGetStarted,
                      icon: const Icon(Icons.upload_outlined),
                      label: const Text('Create Dataset'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: onSeeEvals,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('See Evaluations'),
                    ),
                  ],
                ),
              );

              return Padding(
                padding: const EdgeInsets.all(20),
                child:
                    wide
                        ? Row(
                          children: [
                            Expanded(child: hero),
                            const SizedBox(width: 24),
                            Expanded(child: cta),
                          ],
                        )
                        : SingleChildScrollView(
                          child: Column(
                            children: [hero, const SizedBox(height: 16), cta],
                          ),
                        ),
              );
            },
          ),
        ),
      ),
    );
  }
}
