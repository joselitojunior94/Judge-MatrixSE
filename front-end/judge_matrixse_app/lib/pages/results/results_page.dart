import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../components/glass_card.dart';
import '../../pages/shared/page_body.dart';
import '../../service/auth/auth_service.dart';
import '../../service/api/api.dart' show kApiBaseUrl;

class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key, required this.evalId});
  final int evalId;
  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  Map<String, dynamic>? _results;
  Map<String, dynamic>? _threatReport;
  bool _loading = true;
  String? _err;
  bool _exporting = false;
  final Map<int, Map<String, dynamic>> _diagnoses = {};
  final Set<int> _diagnosing = {};

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
      _results = await AuthService.instance.api.results(widget.evalId);
      final threat = await AuthService.instance.api.threatReport(widget.evalId);
      _threatReport = threat.isEmpty ? null : threat;
    } catch (e) {
      _err = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportJson() async {
    setState(() => _exporting = true);
    try {
      final data = await AuthService.instance.api.exportJson(widget.evalId);
      if (!mounted) return;
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      showDialog(
        context: context,
        builder:
            (_) => Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 800,
                  maxHeight: 600,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text(
                            'JSON Export',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Copy to clipboard',
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: pretty),
                              );
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Copied to clipboard ✓'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_outlined),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            pretty,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Phase 7 — open CSV in browser (triggers download on desktop/web).
  Future<void> _exportCsv() async {
    final url = Uri.parse(
      '$kApiBaseUrl/api/evaluations/${widget.evalId}/export/csv/',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      // Fallback: copy URL to clipboard
      await Clipboard.setData(ClipboardData(text: url.toString()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'URL copied to clipboard — open in browser to download.',
          ),
        ),
      );
    }
  }

  Future<void> _diagnose(int itemId) async {
    setState(() => _diagnosing.add(itemId));
    try {
      final data = await AuthService.instance.api.generateDisagreementDiagnosis(
        widget.evalId,
        itemId,
      );
      if (!mounted) return;
      setState(() => _diagnoses[itemId] = data);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Diagnosis unavailable: $e')));
    } finally {
      if (mounted) setState(() => _diagnosing.remove(itemId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows =
        (_results?['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Scaffold(
      appBar: AppBar(title: Text('Results — Eval ${widget.evalId}')),
      body: PageBody(
        child:
            _loading
                ? const LinearProgressIndicator()
                : _err != null
                ? Text(
                  _err!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
                : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Summary ───────────────────────────────────────
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _stat('Items judged', '${rows.length}'),
                        if (_results?['n_judges'] != null)
                          _stat('Judges', '${_results!['n_judges']}'),
                        if (_results?['unanimous'] != null)
                          _stat('Unanimous', '${_results!['unanimous']}'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_threatReport != null) ...[
                      GlassCard(
                        child: ListTile(
                          leading: const Icon(Icons.verified_outlined),
                          title: const Text('Threats-to-validity report'),
                          subtitle: Text(
                            '${(_threatReport!['report'] as Map?)?['executive_summary'] ?? _threatReport!['markdown'] ?? ''}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: TextButton(
                            onPressed: _showThreatReport,
                            child: const Text('Open'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child:
                          rows.isEmpty
                              ? const Center(
                                child: Text('No judgments recorded yet.'),
                              )
                              : ListView.separated(
                                itemCount: rows.length,
                                separatorBuilder:
                                    (_, __) => const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final r = rows[i];
                                  final counts = (r['counts']
                                          as Map<String, dynamic>)
                                      .entries
                                      .map((e) => '${e.key}: ${e.value}')
                                      .join(', ');
                                  final isUnanimous =
                                      r['is_unanimous'] as bool? ?? false;
                                  final itemId = (r['item_id'] as num).toInt();
                                  final diagnosis = _diagnoses[itemId];
                                  return GlassCard(
                                    child: ExpansionTile(
                                      leading: Icon(
                                        isUnanimous
                                            ? Icons.check_circle_outline
                                            : Icons.how_to_vote_outlined,
                                        color:
                                            isUnanimous ? Colors.green : null,
                                      ),
                                      title: Text(
                                        'Item $itemId — Majority: ${r['majority']}',
                                      ),
                                      subtitle: Text('Votes: $counts'),
                                      trailing:
                                          isUnanimous
                                              ? const Chip(
                                                label: Text('Unanimous'),
                                              )
                                              : null,
                                      children: [
                                        if (!isUnanimous)
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              16,
                                              0,
                                              16,
                                              12,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    const Expanded(
                                                      child: Text(
                                                        'LLM disagreement diagnosis',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                      ),
                                                    ),
                                                    OutlinedButton.icon(
                                                      onPressed:
                                                          _diagnosing.contains(
                                                                itemId,
                                                              )
                                                              ? null
                                                              : () => _diagnose(
                                                                itemId,
                                                              ),
                                                      icon:
                                                          _diagnosing.contains(
                                                                itemId,
                                                              )
                                                              ? const SizedBox(
                                                                width: 16,
                                                                height: 16,
                                                                child:
                                                                    CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2,
                                                                    ),
                                                              )
                                                              : const Icon(
                                                                Icons
                                                                    .psychology_alt_outlined,
                                                              ),
                                                      label: const Text(
                                                        'Diagnose',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                if (diagnosis == null)
                                                  const Text(
                                                    'Advisory only. The LLM explains possible causes and never casts a vote.',
                                                  )
                                                else ...[
                                                  Chip(
                                                    label: Text(
                                                      '${diagnosis['cause']}',
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  SelectableText(
                                                    '${diagnosis['explanation']}',
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _exporting ? null : _exportJson,
                          icon: const Icon(Icons.data_object),
                          label: const Text('View JSON'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _exportCsv,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Download CSV'),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ],
                ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      Text(
        value,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
    ],
  );

  void _showThreatReport() {
    final report = _threatReport;
    if (report == null) return;
    final pretty = const JsonEncoder.withIndent('  ').convert(report);
    final dialogWidth =
        (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 760.0).toDouble();
    showDialog<void>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Threats-to-validity report'),
            content: SizedBox(
              width: dialogWidth,
              child: SingleChildScrollView(
                child: SelectableText(
                  pretty,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }
}
