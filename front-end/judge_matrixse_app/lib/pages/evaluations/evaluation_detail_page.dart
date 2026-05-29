import 'package:flutter/material.dart';

import '../../components/glass_card.dart';
import '../../components/user_avatar.dart';
import '../../pages/items/items_page.dart' show evalRole;
import '../../service/anon/anon_service.dart';
import '../../service/api/api.dart' show apiFileUrl;
import '../../service/auth/auth_service.dart';
import '../../theme/app_theme.dart';

/// Detail/management page for an evaluation.
///
/// Owners can edit the evaluation name, drag people between roles, and control
/// the lifecycle. Non-owners get a read-only member overview.
class EvaluationDetailPage extends StatefulWidget {
  const EvaluationDetailPage({super.key, required this.evalData});
  final Map<String, dynamic> evalData;

  @override
  State<EvaluationDetailPage> createState() => _EvaluationDetailPageState();
}

class _EvaluationDetailPageState extends State<EvaluationDetailPage> {
  late Map<String, dynamic> _ev = Map<String, dynamic>.from(widget.evalData);
  late final TextEditingController _nameCtrl;
  late final TextEditingController _instructionsCtrl;
  final _searchCtrl = TextEditingController();

  List<_Person> _people = [];
  final _evaluators = <_Person>[];
  final _judges = <_Person>[];
  final _reviewers = <_Person>[];
  final _viewers = <_Person>[];
  bool _isPublic = false;
  bool _allowMultipleLabels = false;
  final _publicJoinRoles = <String>{};

  bool _loadingPeople = true;
  bool _loadingCodebooks = false;
  bool _saving = false;
  String? _err;
  List<Map<String, dynamic>> _codebooks = [];

  late final String _role = evalRole(_ev);
  bool get _isOwner => _role == 'owner';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: '${_ev['name'] ?? ''}');
    _instructionsCtrl = TextEditingController(
      text: '${_ev['labeling_instructions'] ?? ''}',
    );
    _allowMultipleLabels = _ev['allow_multiple_labels'] == true;
    _hydratePublicSettings(_ev);
    _hydrateMembers(_ev);
    _loadPeople();
    _loadCodebooks();
    _refresh();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _instructionsCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final fresh = await AuthService.instance.api.getEvaluation(
        _ev['id'] as int,
      );
      if (!mounted) return;
      setState(() {
        _ev = fresh;
        _nameCtrl.text = '${fresh['name'] ?? ''}';
        _instructionsCtrl.text = '${fresh['labeling_instructions'] ?? ''}';
        _allowMultipleLabels = fresh['allow_multiple_labels'] == true;
        _hydratePublicSettings(fresh);
        _hydrateMembers(fresh);
      });
      await _loadCodebooks();
    } catch (_) {
      // Keep initial data if detail reload fails; explicit actions surface errors.
    }
  }

  Future<void> _loadCodebooks() async {
    setState(() => _loadingCodebooks = true);
    try {
      final data = await AuthService.instance.api.codebooks(_ev['id'] as int);
      if (!mounted) return;
      setState(() => _codebooks = data);
    } catch (_) {
      // Codebook is optional; failures should not block evaluation editing.
    } finally {
      if (mounted) setState(() => _loadingCodebooks = false);
    }
  }

  Future<void> _generateCodebook() async {
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      final draft = await AuthService.instance.api.generateCodebook(
        _ev['id'] as int,
        force: true,
      );
      if (!mounted) return;
      await _editCodebook(draft);
      await _loadCodebooks();
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editCodebook(Map<String, dynamic> codebook) async {
    final markdown = await showDialog<String>(
      context: context,
      builder: (_) => _CodebookEditorDialog(codebook: codebook),
    );
    if (markdown == null) return;
    await AuthService.instance.api.updateCodebook(
      codebookId: codebook['id'] as int,
      markdown: markdown,
    );
  }

  Future<void> _publishCodebook(Map<String, dynamic> codebook) async {
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      await AuthService.instance.api.updateCodebook(
        codebookId: codebook['id'] as int,
        status: 'published',
      );
      await _loadCodebooks();
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _hydrateMembers(Map<String, dynamic> ev) {
    _evaluators
      ..clear()
      ..addAll(_peopleFrom(ev['evaluators_detail'] as List? ?? const []));
    _judges
      ..clear()
      ..addAll(_peopleFrom(ev['judges_detail'] as List? ?? const []));
    _reviewers
      ..clear()
      ..addAll(_peopleFrom(ev['reviewers_detail'] as List? ?? const []));
    _viewers
      ..clear()
      ..addAll(_peopleFrom(ev['viewers_detail'] as List? ?? const []));

    if (_judges.isEmpty) {
      _judges.addAll(_idsFallback(ev['judges'] as List? ?? const []));
    }
    if (_reviewers.isEmpty) {
      _reviewers.addAll(_idsFallback(ev['reviewers'] as List? ?? const []));
    }
    if (_viewers.isEmpty) {
      _viewers.addAll(_idsFallback(ev['viewers'] as List? ?? const []));
    }
  }

  void _hydratePublicSettings(Map<String, dynamic> ev) {
    _isPublic = ev['is_public'] == true;
    _publicJoinRoles
      ..clear()
      ..addAll(((ev['public_join_roles'] as List?) ?? []).map((e) => '$e'));
  }

  List<_Person> _peopleFrom(List raw) {
    return raw
        .whereType<Map>()
        .map((e) => _Person.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  List<_Person> _idsFallback(List raw) {
    return raw
        .whereType<num>()
        .map(
          (id) => _Person(
            id: id.toInt(),
            username: 'user_$id',
            displayName: 'User #$id',
          ),
        )
        .toList();
  }

  Future<void> _loadPeople([String query = '']) async {
    if (!_isOwner) {
      setState(() => _loadingPeople = false);
      return;
    }
    setState(() {
      _loadingPeople = true;
      _err = null;
    });
    try {
      final raw = await AuthService.instance.api.userSearch(query);
      if (!mounted) return;
      setState(() => _people = raw.map(_Person.fromJson).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _loadingPeople = false);
    }
  }

  Future<void> _saveAll() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _err = 'Evaluation name is required.');
      return;
    }

    setState(() {
      _saving = true;
      _err = null;
    });

    final judgeIds =
        {
          for (final person in _evaluators) person.id,
          for (final person in _judges) person.id,
        }.toList();

    try {
      final updated = await AuthService.instance.api.updateEvalMembers(
        _ev['id'] as int,
        name: name,
        judges: judgeIds,
        reviewers: _reviewers.map((p) => p.id).toList(),
        viewers: _viewers.map((p) => p.id).toList(),
        isPublic: _isPublic,
        publicJoinRoles: _publicJoinRoles.toList(),
        labelingInstructions: _instructionsCtrl.text.trim(),
        allowMultipleLabels: _allowMultipleLabels,
      );
      if (!mounted) return;
      setState(() {
        _ev = updated;
        _allowMultipleLabels = updated['allow_multiple_labels'] == true;
        _hydratePublicSettings(updated);
        _hydrateMembers(updated);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Evaluation updated.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _doLifecycle(String action) async {
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      final api = AuthService.instance.api;
      final evalId = _ev['id'] as int;
      if (action == 'open') await api.openEval(evalId);
      if (action == 'close') await api.closeEval(evalId);
      if (action == 'freeze') await api.freezeEval(evalId);
      final fresh = await api.getEvaluation(evalId);
      if (!mounted) return;
      setState(() {
        _ev = fresh;
        _hydrateMembers(fresh);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteEvaluation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete evaluation?'),
            content: Text(
              'This will permanently remove "${_nameCtrl.text.trim().isEmpty ? 'this evaluation' : _nameCtrl.text.trim()}" and its evaluation data from the system. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Delete evaluation'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      await AuthService.instance.api.deleteEval(_ev['id'] as int);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _assign(_Role role, _Person person) {
    if (!_isOwner) return;
    setState(() {
      _removeEverywhere(person);
      _listFor(role).add(person);
    });
  }

  void _remove(_Role role, _Person person) {
    if (!_isOwner) return;
    setState(() => _listFor(role).removeWhere((p) => p.id == person.id));
  }

  void _removeEverywhere(_Person person) {
    for (final role in _Role.values) {
      _listFor(role).removeWhere((p) => p.id == person.id);
    }
  }

  List<_Person> _listFor(_Role role) {
    return switch (role) {
      _Role.evaluator => _evaluators,
      _Role.judge => _judges,
      _Role.reviewer => _reviewers,
      _Role.viewer => _viewers,
    };
  }

  Set<int> get _assignedIds => {
    for (final role in _Role.values)
      for (final person in _listFor(role)) person.id,
  };

  @override
  Widget build(BuildContext context) {
    final status = '${_ev['status'] ?? 'draft'}';
    final available =
        _people.where((person) => !_assignedIds.contains(person.id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_nameCtrl.text.isEmpty ? 'Evaluation' : _nameCtrl.text),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _saving ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (_isOwner)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveAll,
                icon:
                    _saving
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.save_outlined),
                label: const Text('Save all'),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
        child: Column(
          children: [
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  _statusChip(status),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      enabled: _isOwner && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Evaluation name',
                        prefixIcon: Icon(Icons.drive_file_rename_outline),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Dataset #${_ev['dataset']}',
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Owner: ${AnonService.nameFromId((_ev['owner'] as Map?)?['id'] as int?)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  TextField(
                    controller: _instructionsCtrl,
                    enabled: _isOwner && !_saving,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Labeling instructions',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.info_outline),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow multiple labels per item'),
                    subtitle: const Text(
                      'Single-label mode remains the default for existing evaluations.',
                    ),
                    value: _allowMultipleLabels,
                    onChanged:
                        _isOwner && !_saving
                            ? (value) =>
                                setState(() => _allowMultipleLabels = value)
                            : null,
                  ),
                ],
              ),
            ),
            if (_isOwner) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (status == 'draft')
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _doLifecycle('open'),
                        icon: const Icon(Icons.play_arrow_outlined),
                        label: const Text('Open for judging'),
                      ),
                    if (status == 'open')
                      FilledButton.icon(
                        onPressed:
                            _saving ? null : () => _doLifecycle('freeze'),
                        icon: const Icon(Icons.ac_unit_outlined),
                        label: const Text('Freeze evaluation'),
                      ),
                    if (status == 'open' || status == 'draft')
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _doLifecycle('close'),
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Close evaluation'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _deleteEvaluation,
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('Delete evaluation'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_isOwner) ...[
              const SizedBox(height: 10),
              _PublicSettingsPanel(
                isPublic: _isPublic,
                roles: _publicJoinRoles,
                onPublicChanged: (value) => setState(() => _isPublic = value),
                onRoleChanged:
                    (role, enabled) => setState(() {
                      if (enabled) {
                        _publicJoinRoles.add(role);
                      } else {
                        _publicJoinRoles.remove(role);
                      }
                    }),
              ),
            ],
            if (_err != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _err!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _CodebookPanel(
              isOwner: _isOwner,
              loading: _loadingCodebooks,
              codebooks: _codebooks,
              onGenerate: _saving ? null : _generateCodebook,
              onEdit: _saving ? null : _editCodebook,
              onPublish: _saving ? null : _publishCodebook,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 1040;
                  final peoplePanel = _PeoplePanel(
                    controller: _searchCtrl,
                    loading: _loadingPeople,
                    people: available,
                    enabled: _isOwner,
                    onSearch: _loadPeople,
                  );
                  final roleGrid = _RoleGrid(
                    editable: _isOwner,
                    evaluators: _evaluators,
                    judges: _judges,
                    reviewers: _reviewers,
                    viewers: _viewers,
                    onAccept: _assign,
                    onRemove: _remove,
                  );

                  if (!wide) {
                    return ListView(
                      children: [
                        if (_isOwner) SizedBox(height: 420, child: peoplePanel),
                        if (_isOwner) const SizedBox(height: 14),
                        SizedBox(height: 760, child: roleGrid),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isOwner) ...[
                        SizedBox(width: 360, child: peoplePanel),
                        const SizedBox(width: 14),
                      ],
                      Expanded(child: roleGrid),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final (icon, color) = switch (status) {
      'open' => (Icons.play_arrow, AppTheme.mint),
      'frozen' => (Icons.ac_unit, AppTheme.cyan),
      'closed' => (Icons.lock, AppTheme.rose),
      'archived' => (Icons.archive_outlined, AppTheme.muted),
      _ => (Icons.drafts_outlined, AppTheme.amber),
    };
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(status),
      backgroundColor: color.withValues(alpha: .13),
      side: BorderSide(color: color.withValues(alpha: .36)),
    );
  }
}

class _CodebookPanel extends StatelessWidget {
  const _CodebookPanel({
    required this.isOwner,
    required this.loading,
    required this.codebooks,
    required this.onGenerate,
    required this.onEdit,
    required this.onPublish,
  });

  final bool isOwner;
  final bool loading;
  final List<Map<String, dynamic>> codebooks;
  final VoidCallback? onGenerate;
  final void Function(Map<String, dynamic> codebook)? onEdit;
  final void Function(Map<String, dynamic> codebook)? onPublish;

  @override
  Widget build(BuildContext context) {
    final published =
        codebooks.where((c) => c['status'] == 'published').toList();
    final latest = codebooks.isEmpty ? null : codebooks.first;
    final visible =
        isOwner ? latest : (published.isEmpty ? null : published.first);
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.amber.withValues(alpha: .16),
            child: const Icon(Icons.menu_book_outlined, color: AppTheme.amber),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Codebook',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (loading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  visible == null
                      ? (isOwner
                          ? 'Generate a draft from completed human judgments, then edit and publish it.'
                          : 'No published codebook yet.')
                      : '${visible['status']} · version ${visible['version']}',
                  style: const TextStyle(color: AppTheme.muted),
                ),
                if (visible != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${visible['markdown'] ?? ''}',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (isOwner)
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onGenerate,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Draft'),
                ),
                if (latest != null)
                  OutlinedButton.icon(
                    onPressed: onEdit == null ? null : () => onEdit!(latest),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                if (latest != null && latest['status'] != 'published')
                  FilledButton.icon(
                    onPressed:
                        onPublish == null ? null : () => onPublish!(latest),
                    icon: const Icon(Icons.publish_outlined),
                    label: const Text('Publish'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PublicSettingsPanel extends StatelessWidget {
  const _PublicSettingsPanel({
    required this.isPublic,
    required this.roles,
    required this.onPublicChanged,
    required this.onRoleChanged,
  });

  final bool isPublic;
  final Set<String> roles;
  final ValueChanged<bool> onPublicChanged;
  final void Function(String role, bool enabled) onRoleChanged;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.travel_explore_outlined, color: AppTheme.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Public participation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Publish this evaluation so other users can discover it and join with an allowed role.',
                  style: TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final role in const ['judge', 'reviewer', 'viewer'])
                      FilterChip(
                        label: Text('Join as $role'),
                        selected: roles.contains(role),
                        onSelected:
                            isPublic
                                ? (enabled) => onRoleChanged(role, enabled)
                                : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Switch(value: isPublic, onChanged: onPublicChanged),
        ],
      ),
    );
  }
}

class _CodebookEditorDialog extends StatefulWidget {
  const _CodebookEditorDialog({required this.codebook});

  final Map<String, dynamic> codebook;

  @override
  State<_CodebookEditorDialog> createState() => _CodebookEditorDialogState();
}

class _CodebookEditorDialogState extends State<_CodebookEditorDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: '${widget.codebook['markdown'] ?? ''}',
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth =
        (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 720.0).toDouble();

    return AlertDialog(
      title: const Text('Edit draft codebook'),
      content: SizedBox(
        width: dialogWidth,
        child: TextField(
          controller: _ctrl,
          minLines: 12,
          maxLines: 18,
          decoration: const InputDecoration(
            alignLabelWithHint: true,
            labelText: 'Markdown reference shown to judges',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save draft'),
        ),
      ],
    );
  }
}

class _PeoplePanel extends StatelessWidget {
  const _PeoplePanel({
    required this.controller,
    required this.loading,
    required this.people,
    required this.enabled,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool loading;
  final List<_Person> people;
  final bool enabled;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_2_outlined, color: AppTheme.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Available people',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            enabled: enabled,
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Search collaborators',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.arrow_forward),
                onPressed:
                    enabled ? () => onSearch(controller.text.trim()) : null,
              ),
            ),
            onSubmitted: enabled ? (value) => onSearch(value.trim()) : null,
          ),
          const SizedBox(height: 12),
          if (loading) const LinearProgressIndicator(),
          if (!loading && people.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No available people. Search by username or create more accounts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.muted),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: people.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final person = people[index];
                  return Draggable<_Person>(
                    data: person,
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(
                        width:
                            MediaQuery.sizeOf(
                              context,
                            ).width.clamp(240.0, 300.0).toDouble(),
                        child: _PersonCard(person: person, elevated: true),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: .35,
                      child: _PersonCard(person: person),
                    ),
                    child: _PersonCard(person: person),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleGrid extends StatelessWidget {
  const _RoleGrid({
    required this.editable,
    required this.evaluators,
    required this.judges,
    required this.reviewers,
    required this.viewers,
    required this.onAccept,
    required this.onRemove,
  });

  final bool editable;
  final List<_Person> evaluators;
  final List<_Person> judges;
  final List<_Person> reviewers;
  final List<_Person> viewers;
  final void Function(_Role role, _Person person) onAccept;
  final void Function(_Role role, _Person person) onRemove;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: MediaQuery.sizeOf(context).width > 1280 ? 2 : 1,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: MediaQuery.sizeOf(context).width > 1280 ? 1.55 : 2.55,
      children: [
        _RoleDropZone(
          editable: editable,
          role: _Role.evaluator,
          people: evaluators,
          icon: Icons.psychology_alt_outlined,
          title: 'Evaluators',
          subtitle: 'Assess items; saved as judges in the current model.',
          accent: AppTheme.mint,
          onAccept: onAccept,
          onRemove: onRemove,
        ),
        _RoleDropZone(
          editable: editable,
          role: _Role.judge,
          people: judges,
          icon: Icons.gavel_outlined,
          title: 'Judges',
          subtitle: 'Assign labels and confidence scores.',
          accent: AppTheme.cyan,
          onAccept: onAccept,
          onRemove: onRemove,
        ),
        _RoleDropZone(
          editable: editable,
          role: _Role.reviewer,
          people: reviewers,
          icon: Icons.rate_review_outlined,
          title: 'Reviewers',
          subtitle: 'Inspect judgments and suggest corrections.',
          accent: AppTheme.rose,
          onAccept: onAccept,
          onRemove: onRemove,
        ),
        _RoleDropZone(
          editable: editable,
          role: _Role.viewer,
          people: viewers,
          icon: Icons.visibility_outlined,
          title: 'Viewers',
          subtitle: 'Read-only access to results and metrics.',
          accent: AppTheme.indigo,
          onAccept: onAccept,
          onRemove: onRemove,
        ),
      ],
    );
  }
}

class _RoleDropZone extends StatelessWidget {
  const _RoleDropZone({
    required this.editable,
    required this.role,
    required this.people,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onAccept,
    required this.onRemove,
  });

  final bool editable;
  final _Role role;
  final List<_Person> people;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final void Function(_Role role, _Person person) onAccept;
  final void Function(_Role role, _Person person) onRemove;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_Person>(
      onWillAcceptWithDetails: (_) => editable,
      onAcceptWithDetails: (details) => onAccept(role, details.data),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color:
                active
                    ? accent.withValues(alpha: .14)
                    : AppTheme.elevated.withValues(alpha: .52),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  active
                      ? accent.withValues(alpha: .86)
                      : Colors.white.withValues(alpha: .10),
              width: active ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: accent.withValues(alpha: .16),
                      child: Icon(icon, color: accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppTheme.muted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${people.length}',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child:
                      people.isEmpty
                          ? Center(
                            child: Text(
                              editable
                                  ? (active
                                      ? 'Drop here'
                                      : 'Drag people into this role')
                                  : 'No members',
                              style: TextStyle(
                                color: active ? accent : AppTheme.muted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                          : ListView.separated(
                            itemCount: people.length,
                            separatorBuilder:
                                (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final person = people[index];
                              return _AssignedPersonCard(
                                person: person,
                                editable: editable,
                                onRemove: () => onRemove(role, person),
                              );
                            },
                          ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, this.elevated = false});

  final _Person person;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: elevated ? .96 : .66),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
        boxShadow:
            elevated
                ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .34),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ]
                : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            _Avatar(person: person, radius: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AnonService.nameFromId(person.id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const Icon(Icons.drag_indicator, color: AppTheme.muted),
          ],
        ),
      ),
    );
  }
}

class _AssignedPersonCard extends StatelessWidget {
  const _AssignedPersonCard({
    required this.person,
    required this.editable,
    required this.onRemove,
  });

  final _Person person;
  final bool editable;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            _Avatar(person: person, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AnonService.nameFromId(person.id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            if (editable)
              IconButton(
                tooltip: 'Remove from role',
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.person, required this.radius});

  final _Person person;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return UserAvatar(
      name: AnonService.nameFromId(person.id),
      avatar: person.avatarUrl,
      radius: radius,
      anonymize: true,
    );
  }
}

enum _Role { evaluator, judge, reviewer, viewer }

class _Person {
  const _Person({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  final int id;
  final String username;
  final String displayName;
  final String? avatarUrl;

  factory _Person.fromJson(Map<String, dynamic> json) {
    final rawAvatar = '${json['avatar'] ?? ''}'.trim();
    final avatar =
        rawAvatar.isEmpty || rawAvatar == 'null' ? null : apiFileUrl(rawAvatar);
    final username = '${json['username']}';
    final display = '${json['display_name'] ?? username}'.trim();
    return _Person(
      id: json['id'] as int,
      username: username,
      displayName: display.isEmpty ? username : display,
      avatarUrl: avatar,
    );
  }

  String get initials {
    final parts =
        displayName
            .trim()
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}
