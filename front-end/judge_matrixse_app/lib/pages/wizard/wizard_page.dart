import 'dart:convert';
import 'dart:io' as uio;
import 'package:csv/csv.dart' as csv;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:judge_matrixse_app/components/glass_card.dart';
import 'package:judge_matrixse_app/components/kv.dart';
import 'package:judge_matrixse_app/components/mapping.dart';
import 'package:judge_matrixse_app/data_structures/column_role.dart';
import 'package:judge_matrixse_app/data_structures/column_spec.dart';
import 'package:judge_matrixse_app/data_structures/selected_csv.dart';
import 'package:judge_matrixse_app/data_structures/upload_mode.dart';
import 'package:judge_matrixse_app/pages/evaluations/create_evaluation_page.dart';
import 'package:judge_matrixse_app/pages/shared/page_container.dart';
import 'package:judge_matrixse_app/service/auth/auth_service.dart';

class WizardPage extends StatefulWidget {
  const WizardPage({super.key});
  @override
  State<WizardPage> createState() => _WizardPageState();
}

class _WizardPageState extends State<WizardPage> {
  UploadMode mode = UploadMode.single;
  String datasetName = 'My Dataset';
  String delimiter = ',';
  String encoding = 'UTF-8';

  String? fileName;
  Uint8List? fileBytes;
  final List<SelectedCsv> batch = [];

  List<String> headers = [];
  List<List<String>> rows = [];
  List<ColumnSpec> columns = [];

  bool busy = false;
  String? info;
  String? err;

  int? lastDatasetId;
  int? lastVersion;

  List<List<String>> _strictParse(String text, String d) {
    final conv = csv.CsvToListConverter(
      fieldDelimiter: d == '\t' ? '\t' : d,
      eol: '\n',
      shouldParseNumbers: false,
    );
    final parsed = conv.convert(text);
    if (parsed.isEmpty) return [];
    final raw = parsed.first.map((e) => e.toString()).toList();
    final hdr = <String>[];
    for (int i = 0; i < raw.length; i++) {
      hdr.add(raw[i].trim().isEmpty ? 'col_$i' : raw[i].trim());
    }
    final H = hdr.length;
    final out = <List<String>>[hdr];
    for (final r in parsed.skip(1)) {
      final rr = r.map((e) => e.toString()).toList();
      if (rr.length > H) {
        out.add(rr.sublist(0, H));
      } else if (rr.length < H) {
        out.add([...rr, ...List.filled(H - rr.length, '')]);
      } else {
        out.add(rr);
      }
    }
    return out;
  }

  String _detectDelimiter(String content) {
    const cands = [',', ';', '\t', '|'];
    final first = content
        .split('\n')
        .firstWhere((e) => e.trim().isNotEmpty, orElse: () => '');
    int best = -1;
    String bestD = ',';
    for (final d in cands) {
      final cnt = first.split(d == '\t' ? '\t' : d).length;
      if (cnt > best) {
        best = cnt;
        bestD = d;
      }
    }
    return bestD;
  }

  Future<void> _pickSingle() async {
    setState(() {
      err = null;
      info = null;
    });
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    fileName = f.name;
    fileBytes =
        f.bytes ??
        (f.path != null && !kIsWeb
            ? await uio.File(f.path!).readAsBytes()
            : null);
    if (fileBytes == null) {
      setState(() => err = 'Failed to read file');
      return;
    }
    String text;
    try {
      text = utf8.decode(fileBytes!);
      encoding = 'UTF-8';
    } catch (_) {
      text = const Latin1Codec().decode(fileBytes!);
      encoding = 'ISO-8859-1';
    }
    delimiter = _detectDelimiter(text);
    final norm = _strictParse(text, delimiter);
    if (norm.isEmpty) {
      setState(() => err = 'Empty CSV');
      return;
    }
    headers = norm.first;
    rows = norm.skip(1).take(20).toList();
    _initColumns();
    setState(() {});
  }

  Future<void> _pickMulti() async {
    setState(() {
      err = null;
      info = null;
    });
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
      allowMultiple: true,
    );
    if (res == null || res.files.isEmpty) return;
    batch.clear();
    List<String>? ref;
    for (final f in res.files) {
      final bytes =
          f.bytes ??
          (f.path != null && !kIsWeb
              ? await uio.File(f.path!).readAsBytes()
              : null);
      if (bytes == null) continue;
      String text;
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        text = const Latin1Codec().decode(bytes);
      }
      final d = _detectDelimiter(text);
      final norm = _strictParse(text, d);
      if (norm.isEmpty) continue;
      final hdr = norm.first;
      final data = norm.skip(1).toList();
      ref ??= hdr;
      final H = ref.length;
      final aligned = [
        for (final r in data)
          (r.length > H
              ? r.sublist(0, H)
              : (r.length < H ? [...r, ...List.filled(H - r.length, '')] : r)),
      ];
      batch.add(
        SelectedCsv(name: f.name, bytes: bytes, headers: ref, allRows: aligned),
      );
    }
    if (batch.isEmpty) {
      setState(() => err = 'No valid CSV');
      return;
    }
    headers = List<String>.from(batch.first.headers);
    rows = [];
    for (final b in batch) {
      for (final r in b.allRows) {
        rows.add(r);
        if (rows.length >= 20) break;
      }
      if (rows.length >= 20) break;
    }
    _initColumns();
    setState(() {});
  }

  void _initColumns() {
    columns = [
      for (final h in headers) ColumnSpec(nameInFile: h, mappedName: h),
    ];
    if (columns.isNotEmpty) columns.first.role = ColumnRole.id;
    final lower = headers.map((e) => e.toLowerCase()).toList();
    for (int i = 0; i < columns.length; i++) {
      final n = lower[i];
      if (n.contains('title') ||
          n.contains('descr') ||
          n.contains('text') ||
          n.contains('message')) {
        columns[i].role = ColumnRole.text;
      }
      if (n == 'label' || n.contains('class') || n.contains('tag')) {
        columns[i].role = ColumnRole.label;
      }
    }
  }

  Uint8List _merge() {
    final d = delimiter == '\t' ? '\t' : delimiter;
    final buf = StringBuffer()..writeln(headers.join(d));
    for (final f in batch) {
      for (final r in f.allRows) {
        buf.writeln(r.join(d));
      }
    }
    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  String? _labelColumnName() {
    for (final c in columns) {
      if (c.role == ColumnRole.label) return c.mappedName ?? c.nameInFile;
    }
    return null;
  }

  Future<void> _send() async {
    if (mode == UploadMode.single && fileBytes == null) return;
    setState(() {
      busy = true;
      err = null;
      info = null;
    });
    try {
      final api = AuthService.instance.api;
      final bytes = mode == UploadMode.single ? fileBytes! : _merge();
      final meta = {
        'delimiter': delimiter,
        'encoding': mode == UploadMode.single ? encoding : 'UTF-8',
        'dataset_name': datasetName,
        'headers_present': true,
        'mode': mode.name,
        'source_count': mode == UploadMode.single ? 1 : batch.length,
        'merge_mode': 'append',
        'merged_client_side': mode == UploadMode.multi,
      };
      final resp = await api.upload(
        bytes: bytes,
        filename:
            mode == UploadMode.single
                ? (fileName ?? 'data.csv')
                : 'merged_${batch.length}.csv',
        meta: meta,
      );
      lastDatasetId = (resp['dataset_id'] as num).toInt();
      lastVersion = (resp['version'] as num).toInt();
      await api.saveMap(lastDatasetId!, lastVersion!, [
        for (final c in columns) c.toJson(),
      ]);
      final labelColumn = _labelColumnName();
      if (labelColumn != null && mounted) {
        await _runLabelNormalizationStep(context, lastDatasetId!, labelColumn);
      }
      info = 'Dataset $lastDatasetId (v$lastVersion) sent and mapped!';
      if (!mounted) return;
      await _promptCreateEval(context, lastDatasetId!);
    } catch (e) {
      err = '$e';
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _runLabelNormalizationStep(
    BuildContext ctx,
    int datasetId,
    String labelColumn,
  ) async {
    final api = AuthService.instance.api;
    Map<String, dynamic> proposal;
    try {
      proposal = await api.generateLabelNormalization(
        datasetId: datasetId,
        labelColumn: labelColumn,
      );
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('Label normalization skipped: $e')),
      );
      return;
    }
    if (!ctx.mounted) return;
    final mapping = <String, String>{
      for (final entry
          in ((proposal['proposed_mapping'] as Map?) ?? {}).entries)
        '${entry.key}': '${entry.value}',
    };
    final decision = await showDialog<_LabelNormalizationDecision>(
      context: ctx,
      barrierDismissible: false,
      builder:
          (_) => _LabelNormalizationDialog(
            proposal: proposal,
            initialMapping: mapping,
          ),
    );
    if (decision == null) return;
    await api.decideLabelNormalization(
      proposalId: proposal['id'] as int,
      status: decision.status,
      mapping: decision.mapping,
    );
  }

  Future<void> _promptCreateEval(BuildContext ctx, int datasetId) async {
    final create = await showDialog<bool>(
      context: ctx,
      builder:
          (_) => AlertDialog(
            title: const Text('Create an evaluation?'),
            content: const Text(
              'Your dataset is saved. Open the role assignment workspace now?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not now'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Assign roles'),
              ),
            ],
          ),
    );
    if (create != true || !ctx.mounted) return;

    final ev = await Navigator.push<Map<String, dynamic>>(
      ctx,
      MaterialPageRoute(
        builder: (_) => CreateEvaluationPage(datasetId: datasetId),
      ),
    );
    if (ev != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('Evaluation created: ${ev['id']}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageContainer(
      title: 'Dataset Wizard',
      subtitle:
          'Upload CSV(s), preview, map columns and generate an Evaluation.',
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<UploadMode>(
                        segments: const [
                          ButtonSegment(
                            value: UploadMode.single,
                            label: Text('1 file'),
                          ),
                          ButtonSegment(
                            value: UploadMode.multi,
                            label: Text('N files'),
                          ),
                        ],
                        selected: {mode},
                        onSelectionChanged:
                            (s) => setState(() => mode = s.first),
                      ),
                      SizedBox(
                        width: 280,
                        child: TextFormField(
                          initialValue: datasetName,
                          decoration: const InputDecoration(
                            labelText: 'Dataset name',
                          ),
                          onChanged: (v) => datasetName = v,
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          initialValue: delimiter,
                          decoration: const InputDecoration(
                            labelText: 'Delimiter',
                          ),
                          items:
                              [',', ';', '\t', '|']
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e == '\t' ? 'Tab' : e),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              (v) => setState(() => delimiter = v ?? ','),
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          initialValue: encoding,
                          decoration: const InputDecoration(
                            labelText: 'Encoding',
                          ),
                          items:
                              ['UTF-8', 'ISO-8859-1', 'Windows-1252']
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              (v) => setState(() => encoding = v ?? 'UTF-8'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GlassCard(
                    child: InkWell(
                      onTap:
                          mode == UploadMode.single ? _pickSingle : _pickMulti,
                      child: Container(
                        height: 130,
                        alignment: Alignment.center,
                        child: Text(
                          headers.isEmpty
                              ? (mode == UploadMode.single
                                  ? 'Click to select one .csv'
                                  : 'Click to select multiple .csv files')
                              : (mode == UploadMode.single
                                  ? 'File: $fileName'
                                  : 'Files: ${batch.length}'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (headers.isNotEmpty) ...[
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        KV('Delimiter', delimiter == '\t' ? 'Tab' : delimiter),
                        KV('Encoding', encoding),
                        KV('Header', '1st line only'),
                        if (mode == UploadMode.multi)
                          KV('Files', '${batch.length}'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Preview (20 lines)',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    GlassCard(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: [
                            for (final h in headers)
                              DataColumn(
                                label: Text(
                                  h,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                          rows:
                              rows
                                  .map(
                                    (r) => DataRow(
                                      cells: [
                                        for (final c in r)
                                          DataCell(
                                            SizedBox(
                                              width: 220,
                                              child: Text(c),
                                            ),
                                          ),
                                      ],
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Column mapping',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Mapping(columns: columns, onChanged: () => setState(() {})),
                    const SizedBox(height: 12),
                    if (err != null)
                      Text(err!, style: const TextStyle(color: Colors.red)),
                    if (info != null)
                      Text(info!, style: const TextStyle(color: Colors.green)),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: busy ? null : _send,
                        icon: const Icon(Icons.cloud_upload),
                        label: const Text('Send and save mapping'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (busy)
            Positioned.fill(
              child: Container(
                color: Colors.white60,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _LabelNormalizationDecision {
  const _LabelNormalizationDecision(this.status, this.mapping);
  final String status;
  final Map<String, String>? mapping;
}

class _LabelNormalizationDialog extends StatefulWidget {
  const _LabelNormalizationDialog({
    required this.proposal,
    required this.initialMapping,
  });

  final Map<String, dynamic> proposal;
  final Map<String, String> initialMapping;

  @override
  State<_LabelNormalizationDialog> createState() =>
      _LabelNormalizationDialogState();
}

class _LabelNormalizationDialogState extends State<_LabelNormalizationDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final entry in widget.initialMapping.entries)
      entry.key: TextEditingController(text: entry.value),
  };

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Map<String, String> _mapping() => {
    for (final entry in _controllers.entries)
      entry.key: entry.value.text.trim(),
  };

  @override
  Widget build(BuildContext context) {
    final dialogWidth =
        (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 620.0).toDouble();
    final compact = MediaQuery.sizeOf(context).width < 560;
    final labels =
        (widget.proposal['distinct_labels'] as List? ?? [])
            .map((e) => '$e')
            .toList();
    return AlertDialog(
      title: const Text('Review label normalization'),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The LLM found pre-existing label values in this CSV. It can only propose a consolidation mapping; you decide whether anything is applied.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final label in labels)
                    Chip(
                      label: Text(label),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              for (final entry in _controllers.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child:
                      compact
                          ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.key,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: entry.value,
                                decoration: const InputDecoration(
                                  labelText: 'Canonical label',
                                  isDense: true,
                                ),
                              ),
                            ],
                          )
                          : Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const Icon(Icons.arrow_forward, size: 16),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: entry.value,
                                  decoration: const InputDecoration(
                                    labelText: 'Canonical label',
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              () => Navigator.pop(
                context,
                const _LabelNormalizationDecision('rejected', null),
              ),
          child: const Text('Reject'),
        ),
        FilledButton.icon(
          onPressed:
              () => Navigator.pop(
                context,
                _LabelNormalizationDecision('approved', _mapping()),
              ),
          icon: const Icon(Icons.check),
          label: const Text('Approve mapping'),
        ),
      ],
    );
  }
}
