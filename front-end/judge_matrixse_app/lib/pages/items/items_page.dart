import 'package:flutter/material.dart';

import '../../components/glass_card.dart';
import '../../components/gradient_background.dart';
import '../../components/section.dart';
import '../../pages/shared/page_body.dart';
import '../../service/anon/anon_service.dart';
import '../../service/auth/auth_service.dart';

/// Derives the current user's role in this evaluation.
/// Returns one of: 'owner', 'judge', 'reviewer', 'viewer', or 'none'.
String evalRole(Map<String, dynamic> evalData) {
  final me = AuthService.instance.currentUser;
  if (me == null) return 'none';
  final myId = me['user_id'] as int?;
  if (myId == null) return 'none';

  final ownerId = (evalData['owner'] as Map?)?['id'];
  if (ownerId == myId) return 'owner';

  final judges = (evalData['judges'] as List?) ?? [];
  final reviewers = (evalData['reviewers'] as List?) ?? [];
  final viewers = (evalData['viewers'] as List?) ?? [];
  final myRoles = ((evalData['my_roles'] as List?) ?? []).map((e) => '$e');

  if (judges.contains(myId)) return 'judge';
  if (reviewers.contains(myId)) return 'reviewer';
  if (viewers.contains(myId)) return 'viewer';
  if (myRoles.contains('judge')) return 'judge';
  if (myRoles.contains('reviewer')) return 'reviewer';
  if (myRoles.contains('viewer')) return 'viewer';
  return 'none';
}

class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key, required this.evalId, required this.evalData});

  final int evalId;

  /// Full evaluation object from /api/evaluations/{id}/ — used to derive role.
  final Map<String, dynamic> evalData;

  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  final _searchCtrl = TextEditingController();
  Map<String, dynamic>? _dataset;
  Map<String, dynamic>? _publishedCodebook;
  List<dynamic> _items = [];
  bool _loading = true;
  String? _err;
  int _page = 1;
  int _totalCount = 0;
  int _completedCount = 0;
  static const int _pageSize = 25;
  String _columnFocus = 'all';

  late final String _role = evalRole(widget.evalData);

  bool get _canJudge => _role == 'owner' || _role == 'judge';
  bool get _canReview => _role == 'owner' || _role == 'reviewer';

  List<Map<String, dynamic>> get _columns =>
      (_dataset?['columns'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final api = AuthService.instance.api;
      final dsId = (widget.evalData['dataset'] as num).toInt();
      _dataset ??= await api.getDataset(dsId);
      final codebooks = await api.codebooks(widget.evalId);
      final published = codebooks.where((c) => c['status'] == 'published');
      _publishedCodebook = published.isEmpty ? null : published.first;
      final res = await api.items(
        widget.evalId,
        page: _page,
        pageSize: _pageSize,
      );
      _totalCount = (res['count'] as num?)?.toInt() ?? 0;
      _completedCount = (res['completed_count'] as num?)?.toInt() ?? 0;
      _items = res['results'] as List;
    } catch (e) {
      _err = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final visibleItems = _filteredItems();
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.evalData['name']} — Labeling'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Chip(
              label: Text(
                _roleLabel(_role),
                style: const TextStyle(fontSize: 12),
              ),
              backgroundColor: _roleColor(_role, context),
            ),
          ),
        ],
      ),
      body: PageBody(
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  _err!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_publishedCodebook != null) ...[
              GlassCard(
                child: ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text('Published codebook'),
                  subtitle: Text(
                    '${_publishedCodebook!['markdown'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(
                    onPressed: () => _showCodebook(_publishedCodebook!),
                    child: const Text('Open'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            _InstructionsCard(
              instructions: _labelingInstructions,
              allowMultipleLabels: _allowMultipleLabels,
              completed: _completedCount,
              total: _totalCount,
            ),
            const SizedBox(height: 8),
            GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Find item on this page',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'all',
                          icon: Icon(Icons.view_agenda_outlined),
                          label: Text('All'),
                        ),
                        ButtonSegment(
                          value: 'text',
                          icon: Icon(Icons.notes_outlined),
                          label: Text('Text'),
                        ),
                        ButtonSegment(
                          value: 'labels',
                          icon: Icon(Icons.label_outline),
                          label: Text('Labels'),
                        ),
                      ],
                      selected: {_columnFocus},
                      onSelectionChanged:
                          (value) => setState(() => _columnFocus = value.first),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child:
                  visibleItems.isEmpty && !_loading
                      ? const Center(child: Text('No items on this page.'))
                      : ListView.separated(
                        itemCount: visibleItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final it = visibleItems[i];
                          return _ItemWorkspaceCard(
                            evalId: widget.evalId,
                            item: it,
                            columns: _columns,
                            focus: _columnFocus,
                            canJudge: _canJudge,
                            canReview: _canReview,
                            onDetails: () => _openDetail(it),
                            allowMultipleLabels: _allowMultipleLabels,
                            onSaveJudgment:
                                (labels, confidence) =>
                                    _saveJudgment(it, labels, confidence),
                            onSaveReview:
                                (acceptedValue, notes) =>
                                    _saveReview(it, acceptedValue, notes),
                          );
                        },
                      ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(
                  onPressed:
                      _page > 1
                          ? () {
                            setState(() => _page--);
                            _load();
                          }
                          : null,
                  child: const Text('Previous'),
                ),
                Text('Page $_page'),
                OutlinedButton(
                  onPressed:
                      _items.length == _pageSize
                          ? () {
                            setState(() => _page++);
                            _load();
                          }
                          : null,
                  child: const Text('Next'),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  bool get _allowMultipleLabels =>
      widget.evalData['allow_multiple_labels'] == true;

  String get _labelingInstructions {
    final value = '${widget.evalData['labeling_instructions'] ?? ''}'.trim();
    if (value.isNotEmpty) return value;
    return 'Assign a short category label to each item, not a long summary. '
        'For GitHub issue datasets, useful examples include: bug, feature, '
        'enhancement, documentation, question, performance, security, and usability.';
  }

  Future<void> _saveJudgment(
    Map<String, dynamic> item,
    List<String> labels,
    double confidence,
  ) async {
    if (labels.isEmpty) return;
    final itemId = (item['id'] as num).toInt();
    try {
      await AuthService.instance.api.judgment(
        widget.evalId,
        itemId,
        value: labels.join(', '),
        labels: labels,
        confidence: confidence,
      );
      if (!mounted) return;
      setState(() {
        final wasPending = item['current_user_judgment'] == null;
        item['current_user_status'] = 'labeled';
        item['current_user_judgment'] = {
          'judge': AuthService.instance.currentUser?['user_id'],
          'value': labels.join(', '),
          'labels': labels,
          'confidence': confidence,
        };
        if (wasPending) _completedCount += 1;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Label saved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _saveReview(
    Map<String, dynamic> item,
    String acceptedValue,
    String notes,
  ) async {
    final itemId = (item['id'] as num).toInt();
    try {
      await AuthService.instance.api.review(
        widget.evalId,
        itemId,
        notes: notes,
        acceptedValue: acceptedValue,
      );
      if (!mounted) return;
      setState(() {
        final wasPending = item['current_user_review'] == null;
        item['current_user_status'] =
            item['current_user_judgment'] != null ? 'labeled' : 'reviewed';
        item['current_user_review'] = {
          'reviewer': AuthService.instance.currentUser?['user_id'],
          'accepted_value': acceptedValue,
          'notes': notes,
        };
        if (wasPending && !_canJudge) _completedCount += 1;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Review saved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  List<Map<String, dynamic>> _filteredItems() {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _items.cast<Map<String, dynamic>>().where((item) {
      if (q.isEmpty) return true;
      final data = (item['data'] as Map).cast<String, dynamic>();
      final haystack =
          [
            '${item['row_index']}',
            for (final entry in data.entries) '${entry.key} ${entry.value}',
          ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  void _showCodebook(Map<String, dynamic> codebook) {
    final dialogWidth =
        (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 680.0).toDouble();
    showDialog<void>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Published codebook'),
            content: SizedBox(
              width: dialogWidth,
              child: SingleChildScrollView(
                child: SelectableText('${codebook['markdown'] ?? ''}'),
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

  // -------------------------------------------------------------------------
  // Detail dialog
  // -------------------------------------------------------------------------
  void _openDetail(Map<String, dynamic> item) {
    final data = (item['data'] as Map).cast<String, dynamic>();
    final roles = {
      for (final c in _columns)
        (c['mapped_name'] ?? c['name_in_file']) as String:
            (c['role'] ?? 'FEATURE') as String,
    };

    Map<String, dynamic> byRole(String role) => {
      for (final e in data.entries)
        if ((roles[e.key] ?? 'FEATURE') == role) e.key: e.value,
    };

    final idMeta = byRole('ID');
    final texts = byRole('TEXT');
    final features = byRole('FEATURE');
    final labels = byRole('LABEL');

    showDialog(
      context: context,
      builder:
          (_) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960, maxHeight: 680),
              child: GradientBackground(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Item #${((item['row_index'] as num?)?.toInt() ?? 0) + 1}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Section(
                                title: 'ID / Meta',
                                child: _kvTable(
                                  idMeta.isEmpty
                                      ? {
                                        'display_item_number':
                                            ((item['row_index'] as num?)
                                                    ?.toInt() ??
                                                0) +
                                            1,
                                      }
                                      : idMeta,
                                ),
                              ),
                              if (texts.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Section(
                                  title: 'Text',
                                  child: _textTable(texts),
                                ),
                              ],
                              if (features.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Section(
                                  title: 'Features',
                                  child: _kvTable(features),
                                ),
                              ],
                              if (labels.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Section(
                                  title: 'Existing labels',
                                  child: _kvTable(labels),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_canJudge)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Use inline labeling form'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  Widget _kvTable(Map<String, dynamic> map) => GlassCard(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(
            label: Text('Field', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          DataColumn(
            label: Text('Value', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
        rows:
            map.entries
                .map(
                  (e) => DataRow(
                    cells: [
                      DataCell(Text(e.key)),
                      DataCell(
                        SizedBox(
                          width:
                              (MediaQuery.sizeOf(context).width - 92)
                                  .clamp(180.0, 560.0)
                                  .toDouble(),
                          child: SelectableText('${e.value}'),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
      ),
    ),
  );

  Widget _textTable(Map<String, dynamic> map) => Column(
    children:
        map.entries
            .map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.key,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        SelectableText('${e.value}'),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
  );

  String _roleLabel(String role) => switch (role) {
    'owner' => '👑 Owner',
    'judge' => '⚖️ Judge',
    'reviewer' => '🔍 Reviewer',
    'viewer' => '👁 Viewer',
    _ => '—',
  };

  Color _roleColor(String role, BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    return switch (role) {
      'owner' => cs.primaryContainer,
      'judge' => cs.secondaryContainer,
      'reviewer' => cs.tertiaryContainer,
      _ => cs.surfaceContainerHighest,
    };
  }
}

class _InstructionsCard extends StatelessWidget {
  const _InstructionsCard({
    required this.instructions,
    required this.allowMultipleLabels,
    required this.completed,
    required this.total,
  });

  final String instructions;
  final bool allowMultipleLabels;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : completed / total;
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Labeling instructions',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(
                    allowMultipleLabels
                        ? 'Multiple labels allowed'
                        : 'Single label only',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(instructions),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: LinearProgressIndicator(value: pct)),
                const SizedBox(width: 12),
                Text('$completed of $total complete'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemWorkspaceCard extends StatefulWidget {
  const _ItemWorkspaceCard({
    required this.evalId,
    required this.item,
    required this.columns,
    required this.focus,
    required this.canJudge,
    required this.canReview,
    required this.allowMultipleLabels,
    required this.onDetails,
    required this.onSaveJudgment,
    required this.onSaveReview,
  });

  final int evalId;
  final Map<String, dynamic> item;
  final List<Map<String, dynamic>> columns;
  final String focus;
  final bool canJudge;
  final bool canReview;
  final bool allowMultipleLabels;
  final VoidCallback onDetails;
  final Future<void> Function(List<String> labels, double confidence)
  onSaveJudgment;
  final Future<void> Function(String acceptedValue, String notes) onSaveReview;

  @override
  State<_ItemWorkspaceCard> createState() => _ItemWorkspaceCardState();
}

class _ItemWorkspaceCardState extends State<_ItemWorkspaceCard> {
  static const _commonLabels = [
    'bug',
    'feature',
    'enhancement',
    'documentation',
    'question',
    'performance',
    'security',
    'usability',
  ];

  late final TextEditingController _labelCtrl;
  late final TextEditingController _reviewLabelCtrl;
  late final TextEditingController _notesCtrl;
  late double _confidence;
  late Set<String> _selectedLabels;
  bool _savingLabel = false;
  bool _savingReview = false;
  List<dynamic> _judgments = [];
  bool _loadingJudgments = false;
  bool _judgementsLoaded = false;

  @override
  void initState() {
    super.initState();
    final labels = _labelsFromJudgment(widget.item['current_user_judgment']);
    _selectedLabels = labels.toSet();
    _labelCtrl = TextEditingController(
      text:
          widget.allowMultipleLabels
              ? ''
              : (labels.isEmpty ? '' : labels.first),
    );
    final review = widget.item['current_user_review'] as Map?;
    _reviewLabelCtrl = TextEditingController(
      text: '${review?['accepted_value'] ?? ''}',
    );
    _notesCtrl = TextEditingController(text: '${review?['notes'] ?? ''}');
    final conf =
        (widget.item['current_user_judgment'] as Map?)?['confidence'] as num?;
    _confidence = (conf ?? 0.8).toDouble();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _reviewLabelCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final data = (item['data'] as Map).cast<String, dynamic>();
    final roles = {
      for (final c in widget.columns)
        '${c['mapped_name'] ?? c['name_in_file']}': '${c['role'] ?? 'FEATURE'}',
    };
    final idFields = _fields(data, roles, 'ID');
    final textFields = _fields(data, roles, 'TEXT');
    final labelFields = _fields(data, roles, 'LABEL');
    final featureFields = _fields(data, roles, 'FEATURE');
    final primaryText =
        textFields.isNotEmpty
            ? textFields.values.first.toString()
            : data.values.take(2).join(' · ');
    final visibleMeta =
        widget.focus == 'labels'
            ? labelFields
            : widget.focus == 'text'
            ? textFields
            : {...idFields, ...labelFields, ...featureFields};
    final displayNumber = ((item['row_index'] as num?)?.toInt() ?? 0) + 1;
    final status = '${item['current_user_status'] ?? 'pending'}';
    final done = status == 'labeled' || status == 'reviewed';

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 860;
            final itemPane = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(radius: 22, child: Text('$displayNumber')),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Item #$displayNumber',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Chip(
                      avatar: Icon(
                        done ? Icons.check_circle_outline : Icons.schedule,
                        size: 16,
                      ),
                      label: Text(done ? _title(status) : 'Pending'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: widget.onDetails,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Details'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SelectableText(
                  primaryText,
                  style: const TextStyle(height: 1.35),
                ),
                if (visibleMeta.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in visibleMeta.entries.take(8))
                        _FieldPill(label: entry.key, value: '${entry.value}'),
                    ],
                  ),
                ],
              ],
            );
            final formPane = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.canJudge) _labelForm(),
                if (widget.canJudge && widget.canReview)
                  const SizedBox(height: 12),
                if (widget.canReview) _reviewForm(),
              ],
            );
            return wide
                ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: itemPane),
                    const SizedBox(width: 18),
                    Expanded(flex: 2, child: formPane),
                  ],
                )
                : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [itemPane, const SizedBox(height: 14), formPane],
                );
          },
        ),
      ),
    );
  }

  Widget _labelForm() => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .045),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: .08)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.allowMultipleLabels ? 'Select labels' : 'Label this item',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final label in _commonLabels)
                FilterChip(
                  label: Text(label),
                  selected:
                      widget.allowMultipleLabels
                          ? _selectedLabels.contains(label)
                          : _labelCtrl.text.trim().toLowerCase() ==
                              label.toLowerCase(),
                  onSelected: (selected) {
                    setState(() {
                      if (widget.allowMultipleLabels) {
                        selected
                            ? _selectedLabels.add(label)
                            : _selectedLabels.remove(label);
                      } else {
                        _labelCtrl.text = label;
                      }
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _labelCtrl,
            decoration: InputDecoration(
              labelText:
                  widget.allowMultipleLabels
                      ? 'Additional labels, comma separated'
                      : 'Custom short category',
              helperText:
                  widget.allowMultipleLabels
                      ? 'Select or type more than one label.'
                      : 'Use one short category.',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Confidence'),
              Expanded(
                child: Slider(
                  value: _confidence,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  label: _confidence.toStringAsFixed(2),
                  onChanged: (value) => setState(() => _confidence = value),
                ),
              ),
              Text(_confidence.toStringAsFixed(2)),
            ],
          ),
          FilledButton.icon(
            onPressed: _savingLabel ? null : _submitJudgment,
            icon:
                _savingLabel
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.check),
            label: const Text('Save label'),
          ),
        ],
      ),
    ),
  );

  Widget _reviewForm() {
    // Load judgments on first render if not yet loaded
    if (!_judgementsLoaded && !_loadingJudgments) {
      Future.microtask(_loadJudgments);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Judge labels section ─────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.how_to_vote_outlined, size: 16),
                const SizedBox(width: 6),
                const Text(
                  'Judge labels',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                if (_loadingJudgments)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (!_loadingJudgments)
                  IconButton(
                    tooltip: 'Refresh',
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      setState(() => _judgementsLoaded = false);
                      _loadJudgments();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_judgments.isEmpty && _judgementsLoaded)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'No labels submitted yet.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              )
            else
              ..._judgments.cast<Map<String, dynamic>>().map((j) {
                final judgeId = j['judge'] as int?;
                final label = '${j['value'] ?? ''}';
                final conf = (j['confidence'] as num?)?.toDouble() ?? 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .10),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            AnonService.nameFromId(judgeId),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(
                            'conf: ${conf.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            const Divider(height: 20),
            // ── Review form ──────────────────────────────────────────────
            const Text(
              'Your review',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reviewLabelCtrl,
              decoration: const InputDecoration(
                labelText: 'Correct label (optional)',
                helperText: 'Leave blank if you agree with the judges.',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Justification / notes',
                helperText: 'Explain why you accept or correct this label.',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _savingReview ? null : _submitReview,
              icon:
                  _savingReview
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.rate_review_outlined),
              label: const Text('Save review'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitJudgment() async {
    final labels = _selectedNormalizedLabels();
    if (labels.isEmpty) return;
    setState(() => _savingLabel = true);
    try {
      await widget.onSaveJudgment(labels, _confidence);
      if (!mounted) return;
      setState(() => _selectedLabels = labels.toSet());
    } finally {
      if (mounted) setState(() => _savingLabel = false);
    }
  }

  Future<void> _submitReview() async {
    setState(() => _savingReview = true);
    try {
      await widget.onSaveReview(_reviewLabelCtrl.text.trim(), _notesCtrl.text);
    } finally {
      if (mounted) setState(() => _savingReview = false);
    }
  }

  Future<void> _loadJudgments() async {
    if (_judgementsLoaded) return;
    setState(() => _loadingJudgments = true);
    try {
      final itemId = (widget.item['id'] as num).toInt();
      final result = await AuthService.instance.api
          .getItemJudgments(widget.evalId, itemId);
      if (mounted) setState(() { _judgments = result; _judgementsLoaded = true; });
    } catch (_) {
      if (mounted) setState(() => _judgementsLoaded = true);
    } finally {
      if (mounted) setState(() => _loadingJudgments = false);
    }
  }

  List<String> _selectedNormalizedLabels() {
    final typed = _labelCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    final values =
        widget.allowMultipleLabels
            ? [..._selectedLabels, ...typed]
            : [_labelCtrl.text.trim()];
    final labels = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final key = value.toLowerCase();
      if (value.isNotEmpty && seen.add(key)) labels.add(value);
    }
    return labels;
  }

  static List<String> _labelsFromJudgment(Object? raw) {
    if (raw is! Map) return [];
    final labels = raw['labels'];
    if (labels is List && labels.isNotEmpty) {
      return labels.map((e) => '$e').where((e) => e.trim().isNotEmpty).toList();
    }
    final value = '${raw['value'] ?? ''}'.trim();
    return value.isEmpty ? [] : [value];
  }

  static String _title(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  Map<String, dynamic> _fields(
    Map<String, dynamic> data,
    Map<String, String> roles,
    String role,
  ) => {
    for (final entry in data.entries)
      if ((roles[entry.key] ?? 'FEATURE') == role) entry.key: entry.value,
  };
}

class _FieldPill extends StatelessWidget {
  const _FieldPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final compact = value.length > 72 ? '${value.substring(0, 72)}...' : value;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          '$label: $compact',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
