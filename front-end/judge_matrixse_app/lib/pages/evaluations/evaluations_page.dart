import 'package:flutter/material.dart';

import '../../components/glass_card.dart';
import '../../components/tutorial_anchor.dart';
import '../../pages/evaluations/create_evaluation_page.dart';
import '../../pages/evaluations/evaluation_chat_page.dart';
import '../../pages/evaluations/evaluation_detail_page.dart';
import '../../pages/items/items_page.dart';
import '../../pages/meta_eval/meta_eval_page.dart';
import '../../pages/metrics/metrics_page.dart';
import '../../pages/results/results_page.dart';
import '../../pages/shared/page_container.dart';
import '../../service/auth/auth_service.dart';
import '../../service/tutorial/tutorial_steps.dart';

class EvaluationsPage extends StatefulWidget {
  const EvaluationsPage({super.key});
  @override
  State<EvaluationsPage> createState() => _EvaluationsPageState();
}

class _EvaluationsPageState extends State<EvaluationsPage> {
  List<Map<String, dynamic>> _evals = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final raw = await AuthService.instance.api.evals();
      _evals = raw.cast<Map<String, dynamic>>();
    } catch (e) {
      _err = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Returns 'owner' | 'judge' | 'reviewer' | 'viewer' | '' for the current user.
  String _myRole(Map<String, dynamic> e) {
    final me = AuthService.instance.currentUser;
    final myId = me?['user_id'] as int?;
    if (myId == null) return '';

    final ownerId = (e['owner'] as Map?)?['id'];
    if (ownerId == myId) return 'owner';

    final judges = (e['judges'] as List?) ?? [];
    final reviewers = (e['reviewers'] as List?) ?? [];
    final viewers = (e['viewers'] as List?) ?? [];
    if (judges.contains(myId)) return 'judge';
    if (reviewers.contains(myId)) return 'reviewer';
    if (viewers.contains(myId)) return 'viewer';
    return '';
  }

  Widget _roleChip(String role, BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    final (label, color) = switch (role) {
      'owner' => ('👑 Owner', cs.primaryContainer),
      'judge' => ('⚖️ Judge', cs.secondaryContainer),
      'reviewer' => ('🔍 Reviewer', cs.tertiaryContainer),
      'viewer' => ('👁 Viewer', cs.surfaceContainerHighest),
      _ => ('—', cs.surfaceContainerHighest),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _statusDot(String status) {
    final color = switch (status) {
      'open' => Colors.green,
      'frozen' => Colors.blue,
      'closed' => Colors.red,
      'archived' => Colors.grey,
      _ => Colors.orange, // draft
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Text(status, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Future<void> _openCreateDialog(BuildContext ctx) async {
    // Fetch available datasets first
    List<Map<String, dynamic>> datasets = [];
    try {
      datasets = await AuthService.instance.api.getDatasets();
    } catch (_) {}

    if (!ctx.mounted) return;

    if (datasets.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text(
            'Upload a dataset first before creating an evaluation.',
          ),
        ),
      );
      return;
    }

    // If only one dataset, go straight to create page; otherwise let user pick
    final int? dsId =
        datasets.length == 1
            ? (datasets.first['id'] as int)
            : await _pickDataset(ctx, datasets);
    if (dsId == null) return;

    if (!ctx.mounted) return;
    final result = await Navigator.push<Map<String, dynamic>>(
      ctx,
      MaterialPageRoute(builder: (_) => CreateEvaluationPage(datasetId: dsId)),
    );
    if (result != null) _load();
  }

  Future<int?> _pickDataset(
    BuildContext ctx,
    List<Map<String, dynamic>> datasets,
  ) {
    return showDialog<int>(
      context: ctx,
      builder:
          (_) => SimpleDialog(
            title: const Text('Select dataset'),
            children:
                datasets
                    .map(
                      (d) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, d['id'] as int),
                        child: Text('${d['name']} (v${d['version']})'),
                      ),
                    )
                    .toList(),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageContainer(
      title: 'Evaluations',
      subtitle: 'Manage your labeling studies.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toolbar
          Row(
            children: [
              TutorialAnchor(
                target: TutorialTarget.evaluationsToolbar,
                child: FilledButton.icon(
                  onPressed: () => _openCreateDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New evaluation'),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_loading) const LinearProgressIndicator(),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _err!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),

          Expanded(
            child:
                _evals.isEmpty && !_loading
                    ? const Center(
                      child: Text(
                        'No evaluations yet.\nUpload a dataset and press "New evaluation".',
                      ),
                    )
                    : ListView.separated(
                      itemCount: _evals.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final e = _evals[i];
                        final evalId = e['id'] as int;
                        final role = _myRole(e);
                        final status = e['status'] as String;
                        final actions = Wrap(
                          spacing: 4,
                          children: [
                            // Detail / manage
                            IconButton(
                              tooltip: 'Details',
                              icon: const Icon(Icons.settings_outlined),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) =>
                                            EvaluationDetailPage(evalData: e),
                                  ),
                                );
                                _load();
                              },
                            ),
                            IconButton(
                              tooltip: 'Participant chat',
                              icon: const Icon(Icons.chat_bubble_outline),
                              onPressed:
                                  () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => EvaluationChatPage(
                                            evalId: evalId,
                                            evalName: e['name'] as String,
                                          ),
                                    ),
                                  ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed:
                                  () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => ItemsPage(
                                            evalId: evalId,
                                            evalData: e,
                                          ),
                                    ),
                                  ),
                              icon: const Icon(Icons.label_outline),
                              label: Text(
                                role == 'reviewer'
                                    ? 'Review items'
                                    : 'Start labeling',
                              ),
                            ),
                            // Metrics
                            IconButton(
                              tooltip: 'Metrics',
                              icon: const Icon(Icons.analytics_outlined),
                              onPressed:
                                  () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => MetricsPage(
                                            evalId: evalId,
                                            evalData: e,
                                          ),
                                    ),
                                  ),
                            ),
                            // Results
                            IconButton(
                              tooltip: 'Results',
                              icon: const Icon(Icons.summarize_outlined),
                              onPressed:
                                  () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => ResultsPage(evalId: evalId),
                                    ),
                                  ),
                            ),
                            // Meta-evaluation (Phase 8)
                            IconButton(
                              tooltip: 'Meta-evaluation (AI analysis)',
                              icon: const Icon(Icons.smart_toy_outlined),
                              onPressed:
                                  () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => MetaEvalPage(
                                            evalId: evalId,
                                            evalName: e['name'] as String,
                                          ),
                                    ),
                                  ),
                            ),
                          ],
                        );

                        return GlassCard(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 720;
                              final actionBar =
                                  i == 0
                                      ? TutorialAnchor(
                                        target:
                                            TutorialTarget.evaluationActions,
                                        child: actions,
                                      )
                                      : actions;
                              final info = Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _statusDot(status),
                                  _roleChip(role, context),
                                  Text(
                                    'Dataset #${e['dataset']}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              );

                              if (compact) {
                                return Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e['name'] as String,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      info,
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: actionBar,
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return ListTile(
                                title: Text(
                                  e['name'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: info,
                                ),
                                trailing: actionBar,
                                isThreeLine: true,
                              );
                            },
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
