import 'package:flutter/material.dart';

import '../../components/glass_card.dart';
import '../../components/user_avatar.dart';
import '../../service/anon/anon_service.dart';
import '../../service/api/api.dart' show apiFileUrl;
import '../../service/auth/auth_service.dart';
import '../../theme/app_theme.dart';

/// Large drag-and-drop workspace for creating a new evaluation.
class CreateEvaluationPage extends StatefulWidget {
  const CreateEvaluationPage({super.key, required this.datasetId});
  final int datasetId;

  @override
  State<CreateEvaluationPage> createState() => _CreateEvaluationPageState();
}

class _CreateEvaluationPageState extends State<CreateEvaluationPage> {
  final _nameCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  List<_Person> _people = [];
  final _evaluators = <_Person>[];
  final _judges = <_Person>[];
  final _reviewers = <_Person>[];
  final _viewers = <_Person>[];

  bool _loadingPeople = true;
  bool _busy = false;
  bool _allowMultipleLabels = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text =
        'Evaluation ${DateTime.now().toIso8601String().substring(0, 19)}';
    _instructionsCtrl.text = _defaultLabelingInstructions;
    _loadPeople();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _instructionsCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPeople([String query = '']) async {
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

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _err = 'Evaluation name is required.');
      return;
    }

    setState(() {
      _busy = true;
      _err = null;
    });

    final judgeIds =
        {
          for (final person in _evaluators) person.id,
          for (final person in _judges) person.id,
        }.toList();

    try {
      final ev = await AuthService.instance.api.createEval(
        name,
        widget.datasetId,
        judges: judgeIds,
        reviewers: _reviewers.map((p) => p.id).toList(),
        viewers: _viewers.map((p) => p.id).toList(),
        labelingInstructions: _instructionsCtrl.text.trim(),
        allowMultipleLabels: _allowMultipleLabels,
      );
      if (!mounted) return;
      await _offerEffortRouting(ev);
      if (!mounted) return;
      Navigator.pop(context, ev);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _offerEffortRouting(Map<String, dynamic> ev) async {
    final api = AuthService.instance.api;
    Map<String, dynamic> suggestion;
    try {
      suggestion = await api.generateEffortRouting(ev['id'] as int);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Routing suggestion skipped: $e')));
      return;
    }
    if (!mounted) return;
    final decision = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RoutingSuggestionDialog(suggestion: suggestion),
    );
    if (decision == null) return;
    await api.decideEffortRouting(
      suggestionId: suggestion['id'] as int,
      status: decision,
    );
  }

  void _assign(_Role role, _Person person) {
    setState(() {
      _removeEverywhere(person);
      _listFor(role).add(person);
    });
  }

  void _remove(_Role role, _Person person) {
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
    final available =
        _people.where((person) => !_assignedIds.contains(person.id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Evaluation'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            label: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon:
                  _busy
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.add_task_rounded),
              label: const Text('Create'),
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
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppTheme.cyan.withValues(alpha: .16),
                    child: const Icon(
                      Icons.rule_folder_outlined,
                      color: AppTheme.cyan,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dataset #${widget.datasetId}',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Evaluation name',
                            prefixIcon: Icon(Icons.drive_file_rename_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _instructionsCtrl,
                          minLines: 3,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Labeling instructions',
                            alignLabelWithHint: true,
                            prefixIcon: Icon(Icons.info_outline),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Allow multiple labels per item'),
                          subtitle: const Text(
                            'Keep off for one short category. Turn on when an item may belong to more than one category.',
                          ),
                          value: _allowMultipleLabels,
                          onChanged:
                              _busy
                                  ? null
                                  : (value) => setState(
                                    () => _allowMultipleLabels = value,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: const Text(
                      'Drag people into roles. Evaluators are added as judges in the current permission model.',
                      style: TextStyle(color: AppTheme.muted),
                    ),
                  ),
                ],
              ),
            ),
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
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 1040;
                  final peoplePanel = _PeoplePanel(
                    controller: _searchCtrl,
                    loading: _loadingPeople,
                    people: available,
                    onSearch: _loadPeople,
                  );
                  final roleGrid = _RoleGrid(
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
                        SizedBox(height: 420, child: peoplePanel),
                        const SizedBox(height: 14),
                        SizedBox(height: 760, child: roleGrid),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 360, child: peoplePanel),
                      const SizedBox(width: 14),
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
}

const _defaultLabelingInstructions =
    'Assign a short category label to each item, not a long summary. '
    'For GitHub issue datasets, useful examples include: bug, feature, '
    'enhancement, documentation, question, performance, security, and usability.';

class _RoutingSuggestionDialog extends StatelessWidget {
  const _RoutingSuggestionDialog({required this.suggestion});

  final Map<String, dynamic> suggestion;

  @override
  Widget build(BuildContext context) {
    final summary = (suggestion['summary'] as Map?) ?? {};
    final scores = (suggestion['item_scores'] as List? ?? []);
    final preview = scores.take(8).toList();
    final dialogWidth =
        (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 680.0).toDouble();
    return AlertDialog(
      title: const Text('Suggested queue routing'),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${summary['suggestion'] ?? 'Review the estimated item difficulty before judges begin.'}',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PctChip(label: 'Low', value: summary['low_contention_pct']),
                  _PctChip(
                    label: 'Medium',
                    value: summary['medium_contention_pct'],
                  ),
                  _PctChip(
                    label: 'High',
                    value: summary['high_contention_pct'],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Preview',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              for (final raw in preview)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .08),
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      title: Text(
                        'Item #${((raw['row_index'] as num?)?.toInt() ?? 0) + 1}',
                      ),
                      subtitle: Text(
                        '${raw['contention']} contention · ${raw['recommended_judges']} judge(s)',
                      ),
                      trailing: Text('${raw['difficulty_score']}'),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              const Text(
                'This does not assign labels and is not visible to judges as a suggested answer.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'ignored'),
          child: const Text('Ignore'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, 'accepted'),
          icon: const Icon(Icons.route_outlined),
          label: const Text('Accept suggestion'),
        ),
      ],
    );
  }
}

class _PctChip extends StatelessWidget {
  const _PctChip({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label ${value ?? 0}%'),
      backgroundColor: AppTheme.elevated.withValues(alpha: .7),
    );
  }
}

class _PeoplePanel extends StatelessWidget {
  const _PeoplePanel({
    required this.controller,
    required this.loading,
    required this.people,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool loading;
  final List<_Person> people;
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
                  'People',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Search collaborators',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => onSearch(controller.text.trim()),
              ),
            ),
            onSubmitted: (value) => onSearch(value.trim()),
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
    required this.evaluators,
    required this.judges,
    required this.reviewers,
    required this.viewers,
    required this.onAccept,
    required this.onRemove,
  });

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
          role: _Role.evaluator,
          people: evaluators,
          icon: Icons.psychology_alt_outlined,
          title: 'Evaluators',
          subtitle: 'Assess items; currently saved as judges.',
          accent: AppTheme.mint,
          onAccept: onAccept,
          onRemove: onRemove,
        ),
        _RoleDropZone(
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
    required this.role,
    required this.people,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onAccept,
    required this.onRemove,
  });

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
            boxShadow: [
              if (active)
                BoxShadow(
                  color: accent.withValues(alpha: .24),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
            ],
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
                              active
                                  ? 'Drop here'
                                  : 'Drag people into this role',
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
  const _AssignedPersonCard({required this.person, required this.onRemove});

  final _Person person;
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
              child: Text(
                AnonService.nameFromId(person.id),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
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
