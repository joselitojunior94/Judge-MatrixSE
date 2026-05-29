import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import 'feedback_form_frame_stub.dart'
    if (dart.library.html) 'feedback_form_frame_web.dart';

const judgematrixseFeedbackFormUrl = 'https://forms.gle/jEiXr25nVtWQH1wE6/';

class FeedbackFormDialog extends StatelessWidget {
  const FeedbackFormDialog({
    super.key,
    required this.onSkip,
    required this.onDone,
  });

  final VoidCallback onSkip;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 24).clamp(280.0, 980.0).toDouble();
    final height = (size.height - 24).clamp(420.0, 780.0).toDouble();
    final compact = size.width < 640;

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(14, compact ? 12 : 16, 10, 10),
              child:
                  compact
                      ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _FeedbackIcon(),
                              const Spacer(),
                              TextButton(
                                onPressed: onSkip,
                                child: const Text('Skip'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const _FeedbackTitle(),
                        ],
                      )
                      : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FeedbackIcon(),
                          const SizedBox(width: 12),
                          const Expanded(child: _FeedbackTitle()),
                          TextButton(
                            onPressed: onSkip,
                            child: const Text('Skip'),
                          ),
                        ],
                      ),
            ),
            const Divider(height: 1),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.all(10),
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  child: FeedbackFormFrame(url: judgematrixseFeedbackFormUrl),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed:
                        () => launchUrl(
                          Uri.parse(judgematrixseFeedbackFormUrl),
                          webOnlyWindowName: '_blank',
                        ),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open in new tab'),
                  ),
                  FilledButton.icon(
                    onPressed: onDone,
                    icon: const Icon(Icons.check),
                    label: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackIcon extends StatelessWidget {
  const _FeedbackIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppTheme.cyan.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.rate_review_outlined, color: AppTheme.cyan),
    );
  }
}

class _FeedbackTitle extends StatelessWidget {
  const _FeedbackTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Help improve JudgeMatrixSE',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 2),
        const Text(
          'This short form opens here so you can answer without leaving your workflow.',
          style: TextStyle(color: AppTheme.muted),
        ),
      ],
    );
  }
}
