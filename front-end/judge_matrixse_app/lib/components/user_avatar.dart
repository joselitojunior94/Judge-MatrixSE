import 'package:flutter/material.dart';

import '../service/api/api.dart' show apiFileUrl;
import '../service/anon/anon_service.dart';
import '../theme/app_theme.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.avatar,
    this.radius = 20,
    this.version = 0,
    this.anonymize = false,
  });

  final String name;
  final String? avatar;
  final double radius;
  final int version;
  /// When true (and [AnonService.enabled]) replaces the avatar with a generic
  /// silhouette and suppresses all identifying information.
  final bool anonymize;

  @override
  Widget build(BuildContext context) {
    if (anonymize && AnonService.enabled) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey.shade700,
        child: Icon(
          Icons.person,
          size: radius * 1.1,
          color: Colors.grey.shade400,
        ),
      );
    }

    final raw = avatar?.trim() ?? '';
    final url = raw.isEmpty || raw == 'null' ? '' : apiFileUrl(raw);
    final bustedUrl = url.isEmpty || version == 0 ? url : '$url?v=$version';

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.cyan.withValues(alpha: .16),
      child: ClipOval(
        child:
            bustedUrl.isEmpty
                ? _Initials(name: name, radius: radius)
                : Image.network(
                  bustedUrl,
                  width: radius * 2,
                  height: radius * 2,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, __, ___) => _Initials(name: name, radius: radius),
                ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name, required this.radius});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Center(
        child: Text(
          _initials(name),
          style: TextStyle(
            color: AppTheme.cyan,
            fontWeight: FontWeight.w900,
            fontSize: radius * .72,
          ),
        ),
      ),
    );
  }

  String _initials(String value) {
    final parts =
        value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}
