import 'package:flutter/material.dart';

import '../service/anon/anon_service.dart';
import '../service/auth/auth_service.dart';
import '../theme/app_theme.dart';
import 'glass_card.dart';
import 'user_avatar.dart';

class NotificationsDialog extends StatefulWidget {
  const NotificationsDialog({super.key});

  @override
  State<NotificationsDialog> createState() => _NotificationsDialogState();
}

class _NotificationsDialogState extends State<NotificationsDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

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
      final data = await AuthService.instance.api.notifications();
      if (!mounted) return;
      setState(() {
        _items =
            ((data['notifications'] as List?) ?? [])
                .cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    await AuthService.instance.api.markNotificationsRead();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 24).clamp(280.0, 620.0).toDouble();
    final height = (size.height - 24).clamp(420.0, 680.0).toDouble();
    final compact = size.width < 520;

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(
                    Icons.notifications_active_outlined,
                    color: AppTheme.cyan,
                  ),
                  Text(
                    'Platform notifications',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  TextButton(
                    onPressed: _markAllRead,
                    child: const Text('Mark all read'),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Expanded(
                child:
                    _items.isEmpty && !_loading
                        ? const Center(
                          child: Text(
                            'No notifications yet.',
                            style: TextStyle(color: AppTheme.muted),
                          ),
                        )
                        : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder:
                              (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final item = _items[index];
                            final actor =
                                item['actor'] as Map<String, dynamic>? ?? {};
                            final unread = item['read_at'] == null;
                            return GlassCard(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  UserAvatar(
                                    name: AnonService.nameFromId(actor['id'] as int?),
                                    avatar: '${actor['avatar'] ?? ''}',
                                    radius: 18,
                                    anonymize: true,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${item['title']}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                            if (unread)
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration: const BoxDecoration(
                                                  color: AppTheme.cyan,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${item['body'] ?? ''}',
                                          style: const TextStyle(
                                            color: AppTheme.muted,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _kindLabel('${item['kind']}'),
                                          style: const TextStyle(
                                            color: AppTheme.cyan,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _kindLabel(String kind) {
    return switch (kind) {
      'profile' => 'Profile',
      'evaluation_invite' => 'Evaluation',
      'evaluation' => 'Evaluation',
      'follow' => 'Follow',
      'chat' => 'Chat',
      'points' => 'Points',
      _ => 'Activity',
    };
  }
}
