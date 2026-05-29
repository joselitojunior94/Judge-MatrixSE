import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class FeedbackFormFrame extends StatelessWidget {
  const FeedbackFormFrame({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: FilledButton.icon(
          onPressed: () => launchUrl(Uri.parse(url)),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open feedback form'),
        ),
      ),
    );
  }
}
