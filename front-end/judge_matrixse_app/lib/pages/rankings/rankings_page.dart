import 'package:flutter/material.dart';

import '../../components/glass_card.dart';
import '../../components/user_avatar.dart';
import '../../pages/people/public_profile_page.dart';
import '../../pages/shared/page_container.dart';
import '../../service/anon/anon_service.dart';
import '../../service/auth/auth_service.dart';
import '../../theme/app_theme.dart';

class RankingsPage extends StatefulWidget {
  const RankingsPage({super.key});

  @override
  State<RankingsPage> createState() => _RankingsPageState();
}

class _RankingsPageState extends State<RankingsPage> {
  Map<String, dynamic>? _platform;
  List<Map<String, dynamic>> _evals = [];
  Map<String, dynamic>? _evaluation;
  int? _selectedEvalId;
  bool _loading = true;
  String? _error;

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
      final api = AuthService.instance.api;
      _platform = await api.platformRankings();
      _evals = (await api.evals()).cast<Map<String, dynamic>>();
      if (_evals.isNotEmpty) {
        _selectedEvalId ??= _evals.first['id'] as int;
        _evaluation = await api.evaluationRankings(_selectedEvalId!);
      }
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadEvaluation(int evalId) async {
    setState(() {
      _selectedEvalId = evalId;
      _evaluation = null;
    });
    try {
      _evaluation = await AuthService.instance.api.evaluationRankings(evalId);
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageContainer(
      title: 'Rankings',
      subtitle:
          'Platform and evaluation leaderboards for the gamification system.',
      child:
          _loading
              ? const LinearProgressIndicator()
              : _error != null
              ? Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
              : LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 980;
                  final platform = _rankingCard(
                    'Most active users',
                    Icons.public_outlined,
                    (_platform?['rankings'] as List?) ?? [],
                  );
                  final evaluation = _evaluationCard(context);
                  return SingleChildScrollView(
                    child:
                        wide
                            ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: platform),
                                const SizedBox(width: 14),
                                Expanded(child: evaluation),
                              ],
                            )
                            : Column(
                              children: [
                                platform,
                                const SizedBox(height: 14),
                                evaluation,
                              ],
                            ),
                  );
                },
              ),
    );
  }

  Widget _evaluationCard(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_outlined, color: AppTheme.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Evaluation rankings',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_evals.isEmpty)
            const Text(
              'No evaluations available.',
              style: TextStyle(color: AppTheme.muted),
            )
          else ...[
            DropdownButtonFormField<int>(
              initialValue: _selectedEvalId,
              decoration: const InputDecoration(labelText: 'Evaluation'),
              items:
                  _evals
                      .map(
                        (e) => DropdownMenuItem<int>(
                          value: e['id'] as int,
                          child: Text('${e['name']}'),
                        ),
                      )
                      .toList(),
              onChanged: (value) {
                if (value != null) _loadEvaluation(value);
              },
            ),
            const SizedBox(height: 14),
            _miniRanking(
              'Most active judges',
              (_evaluation?['judges'] as List?) ?? [],
            ),
            const SizedBox(height: 12),
            _miniRanking(
              'Most active evaluators',
              (_evaluation?['evaluators'] as List?) ?? [],
            ),
            const SizedBox(height: 12),
            _miniRanking(
              'Total activity in evaluation',
              (_evaluation?['total'] as List?) ?? [],
            ),
          ],
        ],
      ),
    );
  }

  Widget _rankingCard(String title, IconData icon, List rows) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const Text(
              'No activity yet.',
              style: TextStyle(color: AppTheme.muted),
            )
          else
            ...rows
                .take(12)
                .toList()
                .asMap()
                .entries
                .map((entry) => _rankRow(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _miniRanking(String title, List rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (rows.isEmpty)
          const Text(
            'No activity yet.',
            style: TextStyle(color: AppTheme.muted),
          )
        else
          ...rows
              .take(5)
              .toList()
              .asMap()
              .entries
              .map((entry) => _rankRow(entry.key, entry.value)),
      ],
    );
  }

  Widget _rankRow(int index, dynamic raw) {
    final row = (raw as Map).cast<String, dynamic>();
    final userId = row['user_id'] as int?;
    final displayName = AnonService.nameFromId(userId);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: () {
        final userId = row['user_id'];
        if (userId is int) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PublicProfilePage(userId: userId),
            ),
          );
        }
      },
      leading: SizedBox(
        width: 46,
        height: 46,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            UserAvatar(
              name: displayName,
              avatar: '${row['avatar'] ?? ''}',
              radius: 19,
              anonymize: true,
            ),
            Positioned(
              right: 0,
              bottom: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      index < 3
                          ? AppTheme.amber
                          : AppTheme.elevated.withValues(alpha: .96),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withValues(alpha: .2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .26),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  '#${index + 1}',
                  style: TextStyle(
                    color: index < 3 ? Colors.black : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      title: Text(displayName),
      subtitle: null,
      trailing: Text(
        '${row['points']} pts',
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: AppTheme.cyan,
        ),
      ),
    );
  }
}
