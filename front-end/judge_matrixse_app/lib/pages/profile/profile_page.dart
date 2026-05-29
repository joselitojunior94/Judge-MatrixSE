import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../components/glass_card.dart';
import '../../components/user_avatar.dart';
import '../../pages/shared/page_container.dart';
import '../../service/anon/anon_service.dart';
import '../../service/auth/auth_service.dart';
import '../../theme/app_theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _displayName = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _message = TextEditingController();
  final _bio = TextEditingController();
  final _orcid = TextEditingController();
  final _linkedin = TextEditingController();
  final _scholar = TextEditingController();
  final _other = TextEditingController();

  String _gender = '';
  Uint8List? _avatarBytes;
  String? _avatarFilename;
  int _avatarVersion = 0;
  Map<String, dynamic>? _profile;
  Map<String, dynamic> _follows = {'following': [], 'followers': []};
  bool _loading = true;
  bool _saving = false;
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
      final profile = await api.me();
      final follows = await api.friends();
      _profile = profile;
      _follows = follows;
      _displayName.text = '${profile['display_name'] ?? ''}';
      _firstName.text = '${profile['first_name'] ?? ''}';
      _lastName.text = '${profile['last_name'] ?? ''}';
      _gender = '${profile['gender'] ?? ''}';
      _message.text = '${profile['profile_message'] ?? ''}';
      _bio.text = '${profile['bio'] ?? ''}';
      _orcid.text = '${profile['orcid'] ?? ''}';
      _linkedin.text = '${profile['linkedin_url'] ?? ''}';
      _scholar.text = '${profile['google_scholar_url'] ?? ''}';
      _other.text = '${profile['other_platform_url'] ?? ''}';
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    setState(() {
      _avatarBytes = file.bytes;
      _avatarFilename = file.name;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await AuthService.instance.api.updateProfile(
        fields: {
          'display_name': _displayName.text.trim(),
          'first_name': _firstName.text.trim(),
          'last_name': _lastName.text.trim(),
          'gender': _gender,
          'profile_message': _message.text.trim(),
          'bio': _bio.text.trim(),
          'orcid': _orcid.text.trim(),
          'linkedin_url': _linkedin.text.trim(),
          'google_scholar_url': _scholar.text.trim(),
          'other_platform_url': _other.text.trim(),
        },
        avatarBytes: _avatarBytes,
        avatarFilename: _avatarFilename,
      );
      _profile = updated;
      _avatarBytes = null;
      _avatarFilename = null;
      _avatarVersion++;
      await AuthService.instance.refreshCurrentUser();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile saved')));
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _syncPublications() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _profile = await AuthService.instance.api.syncPublications(
        orcid: _orcid.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Publications synced from ORCID')),
      );
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _unfollow(int userId) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AuthService.instance.api.unfollowUser(userId);
      _follows = await AuthService.instance.api.friends();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unfollowed')));
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageContainer(
      title: 'Profile',
      subtitle:
          'Academic identity, social links, gamification, followers, and collaborators.',
      child:
          _loading
              ? const LinearProgressIndicator()
              : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth > 920;
                        final profileCard = _profileCard(context);
                        final linksCard = _linksCard(context);
                        return wide
                            ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: profileCard),
                                const SizedBox(width: 14),
                                Expanded(child: linksCard),
                              ],
                            )
                            : Column(
                              children: [
                                profileCard,
                                const SizedBox(height: 14),
                                linksCard,
                              ],
                            );
                      },
                    ),
                    const SizedBox(height: 14),
                    _gamificationCard(context),
                    const SizedBox(height: 14),
                    _followsCard(context),
                  ],
                ),
              ),
    );
  }

  Widget _profileCard(BuildContext context) {
    final displayName =
        _displayName.text.trim().isEmpty
            ? '${_profile?['username'] ?? 'User'}'
            : _displayName.text.trim();

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.person_outline, 'Identity'),
          const SizedBox(height: 12),
          Row(
            children: [
              _avatarBytes != null
                  ? CircleAvatar(
                    radius: 42,
                    backgroundColor: AppTheme.cyan.withValues(alpha: .16),
                    backgroundImage: MemoryImage(_avatarBytes!),
                  )
                  : UserAvatar(
                    name: displayName,
                    avatar: '${_profile?['avatar'] ?? ''}',
                    radius: 42,
                    version: _avatarVersion,
                  ),
              const SizedBox(width: 14),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickPhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Upload photo'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _displayName,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _firstName,
                  decoration: const InputDecoration(labelText: 'First name'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _lastName,
                  decoration: const InputDecoration(labelText: 'Last name'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _gender,
            decoration: const InputDecoration(labelText: 'Gender'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Prefer not to say')),
              DropdownMenuItem(value: 'female', child: Text('Female')),
              DropdownMenuItem(value: 'male', child: Text('Male')),
              DropdownMenuItem(value: 'non_binary', child: Text('Non-binary')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (value) => setState(() => _gender = value ?? ''),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _message,
            maxLength: 280,
            decoration: const InputDecoration(labelText: 'Profile message'),
          ),
          TextField(
            controller: _bio,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Bio'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save profile'),
          ),
        ],
      ),
    );
  }

  Widget _linksCard(BuildContext context) {
    final publications = (_profile?['publications'] as List?) ?? [];
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.school_outlined, 'Academic links'),
          const SizedBox(height: 12),
          TextField(
            controller: _orcid,
            decoration: const InputDecoration(labelText: 'ORCID'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _linkedin,
            decoration: const InputDecoration(labelText: 'LinkedIn URL'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _scholar,
            decoration: const InputDecoration(labelText: 'Google Scholar URL'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _other,
            decoration: const InputDecoration(labelText: 'Other platform URL'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _saving ? null : _syncPublications,
            icon: const Icon(Icons.sync_outlined),
            label: const Text('Retrieve publications from ORCID'),
          ),
          const SizedBox(height: 14),
          Text(
            'Publications (${publications.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (publications.isEmpty)
            const Text(
              'No publications synced yet.',
              style: TextStyle(color: AppTheme.muted),
            )
          else
            ...publications
                .take(8)
                .map(
                  (p) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.article_outlined),
                    title: Text('${p['title']}'),
                    subtitle: Text('${p['year'] ?? ''} ${p['venue'] ?? ''}'),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _gamificationCard(BuildContext context) {
    final badges = (_profile?['badges'] as List?) ?? [];
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.workspace_premium_outlined, 'Gamification'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric('Total points', '${_profile?['total_points'] ?? 0}'),
              _metric('Badges', '${badges.length}'),
              _metric(
                'Badge engine',
                _profile?['badges_ready'] == true ? 'Ready' : 'Off',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (badges.isEmpty)
            const Text(
              'Badges are ready for future rules. Earn activity badges by judging and reviewing.',
              style: TextStyle(color: AppTheme.muted),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  badges
                      .map(
                        (badge) => Chip(
                          avatar: const Icon(
                            Icons.military_tech_outlined,
                            size: 16,
                          ),
                          label: Text('${badge['title']}'),
                        ),
                      )
                      .toList(),
            ),
        ],
      ),
    );
  }

  Widget _followsCard(BuildContext context) {
    final following =
        ((_follows['following'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
    final followers =
        ((_follows['followers'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.group_add_outlined, 'Followers & following'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric('Following', '${following.length}'),
              _metric('Followers', '${followers.length}'),
            ],
          ),
          const SizedBox(height: 14),
          Text('Following', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          if (following.isEmpty)
            const Text(
              'You are not following anyone yet.',
              style: TextStyle(color: AppTheme.muted),
            )
          else
            ...following.map((f) {
              final user = f['following'] as Map<String, dynamic>;
              final anonName = AnonService.nameFromId(user['id'] as int?);
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(anonName),
                trailing: TextButton(
                  onPressed:
                      _saving ? null : () => _unfollow(user['id'] as int),
                  child: const Text('Unfollow'),
                ),
              );
            }),
          const SizedBox(height: 14),
          Text('Followers', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          if (followers.isEmpty)
            const Text(
              'No followers yet.',
              style: TextStyle(color: AppTheme.muted),
            )
          else
            ...followers.map((f) {
              final user = f['follower'] as Map<String, dynamic>;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_add_alt_outlined),
                title: Text(AnonService.nameFromId(user['id'] as int?)),
              );
            }),
        ],
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.cyan),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }

  Widget _metric(String label, String value) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
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
