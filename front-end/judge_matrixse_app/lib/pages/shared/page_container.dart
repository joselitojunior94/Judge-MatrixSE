import 'package:flutter/material.dart';
import 'package:judge_matrixse_app/components/gradient_background.dart';
import 'package:judge_matrixse_app/theme/app_theme.dart';

class PageContainer extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const PageContainer({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isPhone = width < 720;
    final padding = EdgeInsets.all(isPhone ? 10 : 18);

    return GradientBackground(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppTheme.cyan,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            isPhone
                                ? Theme.of(context).textTheme.titleLarge
                                : Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                if (!isPhone) ...[
                  const SizedBox(height: 6),
                  Text(subtitle, style: const TextStyle(color: AppTheme.muted)),
                ],
                SizedBox(height: isPhone ? 10 : 16),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
