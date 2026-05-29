import 'package:flutter/material.dart';

import '../../components/glass_card.dart';
import '../../components/user_avatar.dart';
import '../../pages/items/items_page.dart';
import '../../pages/shared/page_container.dart';
import '../../service/anon/anon_service.dart';
import '../../service/auth/auth_service.dart';
import '../../theme/app_theme.dart';

class PublicEvaluationsPage extends StatefulWidget {
  const PublicEvaluationsPage({super.key});

  @override
  State<PublicEvaluationsPage> createState() => _PublicEvaluationsPageState();
}

class _PublicEvaluationsPageState extends State<PublicEvaluationsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AuthService.instance.api.publicEvaluations();
      if (!mounted) return;
      setState(() => _items = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join(Map<String, dynamic> ev, String role) async {
    try {
      await AuthService.instance.api.joinPublicEvaluation(
        ev['id'] as int,
        role,
      );
      await _load();
      if (!mounted) return;
      final joined = await AuthService.instance.api.getEvaluation(
        ev['id'] as int,
      );
      if (!mounted) return;
      final start = role == 'reviewer' ? 'Review items' : 'Start labeling';
      final openNow = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: Text('Joined as $role'),
              content: Text(
                'You joined "${ev['name']}". You can start working on the evaluation now.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Later'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.label_outline),
                  label: Text(start),
                ),
              ],
            ),
      );
      if (openNow == true && mounted) {
        _openItems(joined);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _startEvaluation(Map<String, dynamic> ev) async {
    try {
      final joined = await AuthService.instance.api.getEvaluation(
        ev['id'] as int,
      );
      if (!mounted) return;
      _openItems(joined);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _openItems(Map<String, dynamic> evaluation) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ItemsPage(
              evalId: evaluation['id'] as int,
              evalData: evaluation,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageContainer(
      title: 'Public evaluations',
      subtitle: 'Discover open studies and join with an available role.',
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Expanded(
            child:
                _items.isEmpty && !_loading
                    ? const Center(
                      child: Text(
                        'No public evaluations yet.',
                        style: TextStyle(color: AppTheme.muted),
                      ),
                    )
                    : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder:
                          (_, index) => _PublicEvaluationCard(
                            evaluation: _items[index],
                            onJoin: (role) => _join(_items[index], role),
                            onStart: () => _startEvaluation(_items[index]),
                          ),
                    ),
          ),
        ],
      ),
    );
  }
}

class _PublicEvaluationCard extends StatelessWidget {
  const _PublicEvaluationCard({
    required this.evaluation,
    required this.onJoin,
    required this.onStart,
  });

  final Map<String, dynamic> evaluation;
  final ValueChanged<String> onJoin;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final owner = evaluation['owner'] as Map<String, dynamic>? ?? {};
    final roles =
        ((evaluation['public_join_roles'] as List?) ?? []).cast<String>();
    final mine = ((evaluation['my_roles'] as List?) ?? []).cast<String>();
    final counts = evaluation['member_counts'] as Map<String, dynamic>? ?? {};

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final profile = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(
                name: AnonService.nameFromId(owner['id'] as int?),
                avatar: '${owner['avatar'] ?? ''}',
                radius: 24,
                anonymize: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${evaluation['name']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Owner: ${AnonService.nameFromId(owner['id'] as int?)} · Dataset: ${evaluation['dataset_name'] ?? evaluation['dataset']}',
                      maxLines: compact ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.muted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text('Judges ${counts['judges'] ?? 0}')),
                        Chip(
                          label: Text('Reviewers ${counts['reviewers'] ?? 0}'),
                        ),
                        Chip(label: Text('Viewers ${counts['viewers'] ?? 0}')),
                        if (mine.isNotEmpty)
                          Chip(label: Text('You: ${mine.join(', ')}')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              for (final role in roles)
                FilledButton.tonal(
                  onPressed: mine.contains(role) ? null : () => onJoin(role),
                  child: Text('Join as $role'),
                ),
              if (mine.contains('judge') || mine.contains('reviewer'))
                FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.label_outline),
                  label: Text(
                    mine.contains('reviewer')
                        ? 'Review items'
                        : 'Start labeling',
                  ),
                ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                profile,
                if (roles.isNotEmpty) ...[const SizedBox(height: 12), actions],
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: profile),
              const SizedBox(width: 12),
              Flexible(child: actions),
            ],
          );
        },
      ),
    );
  }
}
