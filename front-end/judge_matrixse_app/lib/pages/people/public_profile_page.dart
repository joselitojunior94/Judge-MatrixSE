import 'package:flutter/material.dart';

import '../../components/glass_card.dart';
import '../../components/user_avatar.dart';
import '../../pages/shared/page_container.dart';
import '../../service/anon/anon_service.dart';
import '../../service/auth/auth_service.dart';
import '../../theme/app_theme.dart';

class PublicProfilePage extends StatefulWidget {
  const PublicProfilePage({super.key, required this.userId});

  final int userId;

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic> _follows = {'following': [], 'followers': []};
  bool _loading = true;
  bool _savingFollow = false;
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
      _profile = await api.userProfile(widget.userId);
      _follows = await api.userFollows(widget.userId);
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow() async {
    final profile = _profile;
    if (profile == null) return;
    setState(() => _savingFollow = true);
    try {
      if (profile['is_following'] == true) {
        await AuthService.instance.api.unfollowUser(widget.userId);
      } else {
        await AuthService.instance.api.followUser(userId: widget.userId);
      }
      await _load();
    } finally {
      if (mounted) setState(() => _savingFollow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(
        title: Text(profile == null ? 'Profile' : AnonService.nameFromId(widget.userId)),
      ),
      body: PageContainer(
        title: 'Public Profile',
        subtitle: 'Research collaborator profile.',
        child:
            _loading
                ? const LinearProgressIndicator()
                : _error != null
                ? Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
                : profile == null
                ? const Text('Profile not found.')
                : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GlassCard(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            UserAvatar(
                              name: AnonService.nameFromId(widget.userId),
                              avatar: '${profile['avatar'] ?? ''}',
                              radius: 42,
                              anonymize: true,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AnonService.nameFromId(widget.userId),
                                    style:
                                        Theme.of(
                                          context,
                                        ).textTheme.headlineSmall,
                                  ),
                                ],
                              ),
                            ),
                            _metric(
                              'Points',
                              '${profile['total_points'] ?? 0}',
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _savingFollow ? null : _toggleFollow,
                              icon: Icon(
                                profile['is_following'] == true
                                    ? Icons.person_remove_alt_1_outlined
                                    : Icons.person_add_alt_1_outlined,
                              ),
                              label: Text(
                                profile['is_following'] == true
                                    ? 'Unfollow'
                                    : 'Follow',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      GlassCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bio',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${profile['bio'] ?? ''}'.trim().isEmpty
                                  ? 'No bio yet.'
                                  : '${profile['bio']}',
                              style: const TextStyle(color: AppTheme.muted),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Academic links',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if ('${profile['orcid'] ?? ''}'.isNotEmpty)
                                  Chip(
                                    label: Text('ORCID ${profile['orcid']}'),
                                  ),
                                if ('${profile['linkedin_url'] ?? ''}'
                                    .isNotEmpty)
                                  const Chip(label: Text('LinkedIn')),
                                if ('${profile['google_scholar_url'] ?? ''}'
                                    .isNotEmpty)
                                  const Chip(label: Text('Google Scholar')),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      GlassCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Public evaluations',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            ...((_profile?['public_evaluations'] as List?) ??
                                    const [])
                                .cast<Map<String, dynamic>>()
                                .map(
                                  (ev) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.travel_explore_outlined,
                                    ),
                                    title: Text('${ev['name']}'),
                                    subtitle: Text(
                                      'Role: ${((ev['roles'] as List?) ?? []).join(', ')} · ${ev['status']}',
                                    ),
                                    trailing: Text(
                                      '${ev['points'] ?? 0} pts',
                                      style: const TextStyle(
                                        color: AppTheme.cyan,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                            if (((_profile?['public_evaluations'] as List?) ??
                                    const [])
                                .isEmpty)
                              const Text(
                                'No public evaluation participation yet.',
                                style: TextStyle(color: AppTheme.muted),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      GlassCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Publications',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            ...((_profile?['publications'] as List?) ??
                                    const [])
                                .take(12)
                                .map(
                                  (p) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.article_outlined),
                                    title: Text('${p['title']}'),
                                    subtitle: Text(
                                      '${p['year'] ?? ''} ${p['venue'] ?? ''}',
                                    ),
                                  ),
                                ),
                            if (((_profile?['publications'] as List?) ??
                                    const [])
                                .isEmpty)
                              const Text(
                                'No synced publications.',
                                style: TextStyle(color: AppTheme.muted),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      GlassCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Network',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _metric(
                                  'Following',
                                  '${((_follows['following'] as List?) ?? const []).length}',
                                ),
                                _metric(
                                  'Followers',
                                  '${((_follows['followers'] as List?) ?? const []).length}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Followers',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            ...(((_follows['followers'] as List?) ?? const [])
                                .cast<Map<String, dynamic>>()
                                .take(8)
                                .map((f) {
                                  final user =
                                      f['follower'] as Map<String, dynamic>;
                                  final anonName = AnonService.nameFromId(user['id'] as int?);
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.person_outline),
                                    title: Text(anonName),
                                  );
                                })),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            Text(
              label,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
