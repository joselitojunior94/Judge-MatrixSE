import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../components/glass_card.dart';
import '../../pages/shared/page_body.dart';
import '../../service/anon/anon_service.dart';
import '../../service/auth/auth_service.dart';

/// Phase 8 — LLM Meta-Evaluation dashboard.
///
/// Safety note (shown to user):
///   All analysis is advisory only. The LLM NEVER casts a vote or assigns a
///   label that counts toward Cohen's κ. Results are stored separately and
///   clearly marked as AI-generated.
class MetaEvalPage extends StatefulWidget {
  const MetaEvalPage({
    super.key,
    required this.evalId,
    required this.evalName,
  });

  final int evalId;
  final String evalName;

  @override
  State<MetaEvalPage> createState() => _MetaEvalPageState();
}

class _MetaEvalPageState extends State<MetaEvalPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 6, vsync: this);

  static const _tabs = [
    _FeatureTab('Disagreement', Icons.compare_arrows_outlined),
    _FeatureTab('Effort',       Icons.timer_outlined),
    _FeatureTab('Consistency',  Icons.person_search_outlined),
    _FeatureTab('Codebook',     Icons.book_outlined),
    _FeatureTab('Validity',     Icons.verified_outlined),
    _FeatureTab('Normalise',    Icons.auto_fix_high_outlined),
  ];

  final Map<int, Map<String, dynamic>?> _results = {};
  final Map<int, bool>   _loading  = {};
  final Map<int, String?> _errors  = {};
  Map<String, dynamic>? _evaluation;
  int? _selectedJudgeId;
  List<Map<String, dynamic>> _consistencyFindings = [];

  @override
  void initState() {
    super.initState();
    _loadEvaluation();
  }

  Future<void> _loadEvaluation() async {
    try {
      final ev = await AuthService.instance.api.getEvaluation(widget.evalId);
      if (!mounted) return;
      final judges = (ev['judges_detail'] as List? ?? ev['judges'] as List? ?? []);
      setState(() {
        _evaluation = ev;
        if (_selectedJudgeId == null && judges.isNotEmpty) {
          final first = judges.first;
          _selectedJudgeId =
              first is Map ? first['id'] as int? : (first as num).toInt();
        }
      });
    } catch (_) {
      // The ordinary tabs can still run; consistency will show empty state.
    }
  }

  Future<void> _fetch(int index) async {
    setState(() { _loading[index] = true; _errors[index] = null; });
    try {
      final api = AuthService.instance.api;
      final id  = widget.evalId;
      final data = await switch (index) {
        0 => api.metaDisagreement(id),
        1 => api.metaEffort(id),
        2 => api.metaConsistency(id),
        3 => api.metaCodebook(id),
        4 => api.metaValidity(id),
        5 => api.metaNormalise(id),
        _ => Future.value(<String, dynamic>{}),
      };
      setState(() => _results[index] = data);
    } catch (e) {
      setState(() => _errors[index] = '$e');
    } finally {
      if (mounted) setState(() => _loading[index] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Meta-Eval — ${widget.evalName}'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: _tabs
              .map((t) => Tab(icon: Icon(t.icon, size: 16), text: t.label))
              .toList(),
        ),
      ),
      body: Column(children: [
        // Safety banner
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.tertiaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            Icon(Icons.info_outline,
                size: 14,
                color: Theme.of(context).colorScheme.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'AI analysis only — never counts as a judgment. '
                'All outputs marked with model name + prompt version.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ]),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: List.generate(6, _buildTab),
          ),
        ),
      ]),
    );
  }

  Widget _buildTab(int index) {
    if (index == 2) return _buildConsistencyTab();
    final loading = _loading[index] ?? false;
    final error   = _errors[index];
    final result  = _results[index];

    return PageBody(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 12),
        if (result == null && !loading && error == null)
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(_tabs[index].icon, size: 48,
                  color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(_tabs[index].label,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => _fetch(index),
                icon: const Icon(Icons.play_arrow_outlined),
                label: const Text('Run analysis'),
              ),
            ]),
          ),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (error != null)
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(error,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ),
          ),
        if (result != null) ...[
          _LlmMetaBadge(result['llm_meta'] as Map<String, dynamic>?),
          const SizedBox(height: 8),
          Expanded(child: _ResultViewer(result: result)),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () => _fetch(index),
              icon: const Icon(Icons.refresh),
              label: const Text('Re-run'),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Copy JSON',
              icon: const Icon(Icons.copy_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(
                    text: const JsonEncoder.withIndent('  ').convert(result)));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard ✓')));
              },
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _buildConsistencyTab() {
    final judges = (_evaluation?['judges_detail'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final loading = _loading[2] ?? false;
    final error = _errors[2];
    return PageBody(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 12),
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedJudgeId,
                  decoration: const InputDecoration(labelText: 'Judge'),
                  items: [
                    for (final judge in judges)
                      DropdownMenuItem(
                        value: judge['id'] as int,
                        child: Text(AnonService.nameFromId(judge['id'] as int?)),
                      ),
                  ],
                  onChanged: (value) => setState(() => _selectedJudgeId = value),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed:
                    loading || _selectedJudgeId == null
                        ? null
                        : _runConsistencyAudit,
                icon:
                    loading
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.person_search_outlined),
                label: const Text('Run audit'),
              ),
            ]),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 12),
        Expanded(
          child:
              _consistencyFindings.isEmpty
                  ? const Center(
                    child: Text('Run an audit to find same-judge inconsistencies.'),
                  )
                  : ListView.separated(
                    itemCount: _consistencyFindings.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final finding = _consistencyFindings[index];
                      return GlassCard(
                        child: ListTile(
                          leading: const Icon(Icons.compare_arrows_outlined),
                          title: Text(
                            'Items ${finding['item_a']} and ${finding['item_b']}',
                          ),
                          subtitle: Text(
                            '${finding['label_a']} vs ${finding['label_b']}\n${finding['justification']}',
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (status) => _resolveFinding(finding, status),
                            itemBuilder:
                                (_) => const [
                                  PopupMenuItem(
                                    value: 'corrected',
                                    child: Text('Mark corrected'),
                                  ),
                                  PopupMenuItem(
                                    value: 'genuinely_different',
                                    child: Text('Genuinely different'),
                                  ),
                                  PopupMenuItem(
                                    value: 'dismissed',
                                    child: Text('Dismiss'),
                                  ),
                                ],
                          ),
                        ),
                      );
                    },
                  ),
        ),
      ]),
    );
  }

  Future<void> _runConsistencyAudit() async {
    setState(() { _loading[2] = true; _errors[2] = null; });
    try {
      final data = await AuthService.instance.api.generateConsistencyAudit(
        evalId: widget.evalId,
        judgeId: _selectedJudgeId!,
      );
      if (!mounted) return;
      setState(() => _consistencyFindings = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errors[2] = '$e');
    } finally {
      if (mounted) setState(() => _loading[2] = false);
    }
  }

  Future<void> _resolveFinding(
    Map<String, dynamic> finding,
    String status,
  ) async {
    try {
      final updated = await AuthService.instance.api.resolveConsistencyFinding(
        findingId: finding['id'] as int,
        status: status,
      );
      if (!mounted) return;
      setState(() {
        final idx = _consistencyFindings.indexWhere((e) => e['id'] == updated['id']);
        if (idx >= 0) _consistencyFindings[idx] = updated;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update finding: $e')),
      );
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ──────────────────────────────────────────────────────────────────────────────

class _FeatureTab {
  const _FeatureTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _LlmMetaBadge extends StatelessWidget {
  const _LlmMetaBadge(this.meta);
  final Map<String, dynamic>? meta;

  @override
  Widget build(BuildContext context) {
    if (meta == null) return const SizedBox.shrink();
    return Wrap(spacing: 6, children: [
      Chip(
        avatar: const Icon(Icons.smart_toy_outlined, size: 14),
        label: Text('${meta!['provider']} / ${meta!['model']}',
            style: const TextStyle(fontSize: 11)),
        backgroundColor:
            Theme.of(context).colorScheme.secondaryContainer,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      ),
      Chip(
        label: Text('prompt v${meta!['prompt_version']}',
            style: const TextStyle(fontSize: 11)),
        backgroundColor:
            Theme.of(context).colorScheme.surfaceContainerHighest,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      ),
      if (meta!['duration_ms'] != null)
        Chip(
          label: Text('${meta!['duration_ms']} ms',
              style: const TextStyle(fontSize: 11)),
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        ),
    ]);
  }
}

class _ResultViewer extends StatelessWidget {
  const _ResultViewer({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    // Try to parse the LLM text as JSON for pretty display
    final rawText = result['analysis'] as String? ?? '';
    dynamic parsed;
    try {
      parsed = jsonDecode(rawText);
    } catch (_) {
      parsed = null;
    }

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Numeric stats (non-LLM fields)
        ..._statsCards(context, result),
        const SizedBox(height: 12),
        // LLM output
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              parsed != null
                  ? const JsonEncoder.withIndent('  ').convert(parsed)
                  : rawText,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ]),
    );
  }

  List<Widget> _statsCards(BuildContext ctx, Map<String, dynamic> data) {
    final interesting = data.entries.where((e) =>
        e.key != 'analysis' &&
        e.key != 'llm_meta' &&
        e.value != null).toList();
    if (interesting.isEmpty) return [];
    return [
      GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: interesting.map((e) {
              final val = e.value;
              if (val is Map || val is List) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.key,
                          style: const TextStyle(fontWeight: FontWeight.w600,
                              fontSize: 12)),
                      const SizedBox(height: 2),
                      SelectableText(
                        const JsonEncoder.withIndent('  ').convert(val),
                        style: const TextStyle(fontSize: 11,
                            fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Text('${e.key}: ',
                      style: const TextStyle(fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  Expanded(child: Text('$val',
                      style: const TextStyle(fontSize: 13))),
                ]),
              );
            }).toList(),
          ),
        ),
      ),
    ];
  }
}
