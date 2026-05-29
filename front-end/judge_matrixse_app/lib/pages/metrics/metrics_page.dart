import 'package:flutter/material.dart';

import '../../components/glass_card.dart';
import '../../pages/shared/page_body.dart';
import '../../service/anon/anon_service.dart';
import '../../service/auth/auth_service.dart';
import '../items/items_page.dart' show evalRole;

class MetricsPage extends StatefulWidget {
  const MetricsPage({
    super.key,
    required this.evalId,
    required this.evalData,
  });

  final int evalId;
  final Map<String, dynamic> evalData;

  @override
  State<MetricsPage> createState() => _MetricsPageState();
}

class _MetricsPageState extends State<MetricsPage> {
  Map<String, dynamic>? _metrics;
  bool _loading = true;
  String? _err;

  late final String _role = evalRole(widget.evalData);
  bool get _isOwner => _role == 'owner';
  bool get _isClosed => widget.evalData['status'] == 'closed';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _err = null; });
    try {
      _metrics = await AuthService.instance.api.metrics(widget.evalId);
    } catch (e) {
      _err = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _closeEval() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Close evaluation?'),
        content: const Text(
            'Closing stops all new judgments and reviews. '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Close')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuthService.instance.api.closeEval(widget.evalId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Evaluation closed ✓')));
      setState(() => widget.evalData['status'] = 'closed');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pairs = (_metrics?['pairs'] as List?)?.cast<Map<String, dynamic>>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Metrics — ${widget.evalData['name']}'),
      ),
      body: PageBody(
        child: _loading
            ? const LinearProgressIndicator()
            : _err != null
                ? Text(_err!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error))
                : Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary row
                      Wrap(spacing: 16, runSpacing: 8, children: [
                        _stat('Items used',
                            '${_metrics!['items_used']}'),
                        _stat('Judge pairs', '${pairs?.length ?? 0}'),
                        _stat('Status', widget.evalData['status'] as String),
                      ]),
                      const SizedBox(height: 12),
                      const Text('Cohen\'s κ — pairwise',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Expanded(
                        child: ListView(children: [
                          // ── Cohen's κ pairwise ────────────────────────
                          if (pairs == null || pairs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                  child: Text(
                                      'Not enough judges with overlapping items yet.')),
                            )
                          else
                            ...pairs.map((p) {
                              final kappa = p['cohen_kappa'];
                              final kappaStr = kappa == null
                                  ? 'n/a'
                                  : (kappa as num).toStringAsFixed(3);
                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 8),
                                child: GlassCard(
                                  child: ListTile(
                                    title:
                                        Text('Judges ${AnonService.anonymiseJudgeList('${p['judges']}')}'),
                                    subtitle: Text('κ = $kappaStr'),
                                    trailing: kappa == null
                                        ? null
                                        : _kappaChip(
                                            kappa as double, context),
                                  ),
                                ),
                              );
                            }),
                          // ── Per-label breakdown (Phase 6) ─────────────
                          if ((_metrics?['per_label']
                                  as Map?)
                              ?.isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 8),
                            const Text('Per-label statistics',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            ...(_metrics!['per_label']
                                    as Map<String, dynamic>)
                                .entries
                                .map((entry) {
                              final stats = entry.value
                                  as Map<String, dynamic>;
                              final count =
                                  stats['count'] as int? ?? 0;
                              final judges = AnonService.anonymiseJudgeList(
                                  (stats['judges'] as List?)?.join(', ') ?? '');
                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 6),
                                child: GlassCard(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    child: Row(children: [
                                      Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment
                                                    .start,
                                            children: [
                                              Text(entry.key,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight
                                                              .w600)),
                                              if (judges.isNotEmpty)
                                                Text(
                                                    'Judges: $judges',
                                                    style:
                                                        const TextStyle(
                                                            fontSize:
                                                                12,
                                                            color: Colors
                                                                .grey)),
                                            ]),
                                      ),
                                      Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text('$count',
                                                style: const TextStyle(
                                                    fontSize: 22,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            const Text('votes',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey)),
                                          ]),
                                    ]),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 8),
                      // Action row
                      Row(children: [
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                        ),
                        const Spacer(),
                        if (_isOwner && !_isClosed)
                          FilledButton.icon(
                            onPressed: _closeEval,
                            icon: const Icon(Icons.lock_outline),
                            label: const Text('Close evaluation'),
                          ),
                        if (_isClosed)
                          const Chip(label: Text('Closed 🔒')),
                      ]),
                    ]),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700)),
        ],
      );

  Widget _kappaChip(double kappa, BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    final (label, color) = kappa >= 0.8
        ? ('Excellent', cs.primaryContainer)
        : kappa >= 0.6
            ? ('Good', cs.secondaryContainer)
            : kappa >= 0.4
                ? ('Fair', cs.tertiaryContainer)
                : ('Poor', cs.errorContainer);
    return Chip(label: Text(label), backgroundColor: color);
  }
}
