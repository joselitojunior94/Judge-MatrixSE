import 'package:flutter/material.dart';

import '../../components/glass_card.dart';
import '../../components/user_avatar.dart';
import '../../pages/people/public_profile_page.dart';
import '../../pages/shared/page_container.dart';
import '../../service/anon/anon_service.dart';
import '../../service/auth/auth_service.dart';
import '../../theme/app_theme.dart';

class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key});

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _evals = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    try {
      final api = AuthService.instance.api;
      _people = await api.userSearch('');
      _evals = (await api.evals()).cast<Map<String, dynamic>>();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _people = await AuthService.instance.api.userSearch(
        _searchCtrl.text.trim(),
      );
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow(Map<String, dynamic> person) async {
    try {
      final isFollowing = person['is_following'] == true;
      if (isFollowing) {
        await AuthService.instance.api.unfollowUser(person['id'] as int);
      } else {
        await AuthService.instance.api.followUser(userId: person['id'] as int);
      }
      setState(() => person['is_following'] = !isFollowing);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFollowing
                ? 'Unfollowed ${AnonService.nameFromId(person['id'] as int?)}'
                : 'Now following ${AnonService.nameFromId(person['id'] as int?)}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _addToEvaluation(Map<String, dynamic> person) async {
    if (_evals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No evaluations available.')),
      );
      return;
    }
    final choice = await showDialog<_EvalRoleChoice>(
      context: context,
      builder: (_) => _EvaluationRoleDialog(evaluations: _evals),
    );
    if (choice == null) return;

    try {
      final api = AuthService.instance.api;
      final ev = await api.getEvaluation(choice.evalId);
      final userId = person['id'] as int;
      final judges = _ids(ev['judges']);
      final reviewers = _ids(ev['reviewers']);
      final viewers = _ids(ev['viewers']);
      if (choice.role == 'judge' || choice.role == 'evaluator') {
        if (!judges.contains(userId)) judges.add(userId);
      } else if (choice.role == 'reviewer') {
        if (!reviewers.contains(userId)) reviewers.add(userId);
      } else if (choice.role == 'viewer') {
        if (!viewers.contains(userId)) viewers.add(userId);
      }
      await api.updateEvalMembers(
        choice.evalId,
        judges: judges,
        reviewers: reviewers,
        viewers: viewers,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AnonService.nameFromId(person['id'] as int?)} added as ${choice.role}.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  List<int> _ids(dynamic raw) =>
      ((raw as List?) ?? const [])
          .whereType<num>()
          .map((e) => e.toInt())
          .toList();

  @override
  Widget build(BuildContext context) {
    return PageContainer(
      title: 'People',
      subtitle:
          'Find profiles, follow collaborators, and add people to evaluations.',
      child: Column(
        children: [
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Search by name, display name, or username',
                      prefixIcon: Icon(Icons.person_search_outlined),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _loading ? null : _search,
                  icon: const Icon(Icons.search),
                  label: const Text('Search'),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child:
                _people.isEmpty && !_loading
                    ? const Center(child: Text('No people found.'))
                    : ListView.separated(
                      itemCount: _people.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final person = _people[index];
                        return _PersonResultCard(
                          person: person,
                          onProfile:
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => PublicProfilePage(
                                        userId: person['id'] as int,
                                      ),
                                ),
                              ),
                          onFollow: () => _toggleFollow(person),
                          onEvaluation: () => _addToEvaluation(person),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

class _PersonResultCard extends StatelessWidget {
  const _PersonResultCard({
    required this.person,
    required this.onProfile,
    required this.onFollow,
    required this.onEvaluation,
  });

  final Map<String, dynamic> person;
  final VoidCallback onProfile;
  final VoidCallback onFollow;
  final VoidCallback onEvaluation;

  @override
  Widget build(BuildContext context) {
    final userId = person['id'] as int?;
    final anonName = AnonService.nameFromId(userId);
    final following = person['is_following'] == true;
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          UserAvatar(
            name: anonName,
            avatar: '${person['avatar'] ?? ''}',
            radius: 26,
            anonymize: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onProfile,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    anonName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    anonName.toLowerCase().replaceAll(' ', '_'),
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                ],
              ),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: onProfile,
                icon: const Icon(Icons.person_outline),
                label: const Text('Profile'),
              ),
              OutlinedButton.icon(
                onPressed: onFollow,
                icon: Icon(
                  following
                      ? Icons.person_remove_alt_1_outlined
                      : Icons.person_add_alt_1_outlined,
                ),
                label: Text(following ? 'Unfollow' : 'Follow'),
              ),
              FilledButton.icon(
                onPressed: onEvaluation,
                icon: const Icon(Icons.playlist_add),
                label: const Text('Add to evaluation'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EvaluationRoleDialog extends StatefulWidget {
  const _EvaluationRoleDialog({required this.evaluations});

  final List<Map<String, dynamic>> evaluations;

  @override
  State<_EvaluationRoleDialog> createState() => _EvaluationRoleDialogState();
}

class _EvaluationRoleDialogState extends State<_EvaluationRoleDialog> {
  late int _evalId = widget.evaluations.first['id'] as int;
  String _role = 'reviewer';

  @override
  Widget build(BuildContext context) {
    final dialogWidth =
        (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 440.0).toDouble();

    return AlertDialog(
      title: const Text('Add to evaluation'),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _evalId,
              decoration: const InputDecoration(labelText: 'Evaluation'),
              items:
                  widget.evaluations
                      .map(
                        (e) => DropdownMenuItem<int>(
                          value: e['id'] as int,
                          child: Text('${e['name']}'),
                        ),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _evalId = value ?? _evalId),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: 'reviewer', child: Text('Reviewer')),
                DropdownMenuItem(value: 'judge', child: Text('Judge')),
                DropdownMenuItem(value: 'evaluator', child: Text('Evaluator')),
                DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
              ],
              onChanged: (value) => setState(() => _role = value ?? _role),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              () => Navigator.pop(context, _EvalRoleChoice(_evalId, _role)),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _EvalRoleChoice {
  const _EvalRoleChoice(this.evalId, this.role);
  final int evalId;
  final String role;
}
