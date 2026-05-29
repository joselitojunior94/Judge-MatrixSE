import 'dart:async';

import 'package:flutter/material.dart';

import '../../components/glass_card.dart';
import '../../components/gradient_background.dart';
import '../../components/user_avatar.dart';
import '../../service/anon/anon_service.dart';
import '../../service/api/api.dart' show apiFileUrl;
import '../../service/auth/auth_service.dart';
import '../../theme/app_theme.dart';

class EvaluationChatPage extends StatefulWidget {
  const EvaluationChatPage({
    super.key,
    required this.evalId,
    required this.evalName,
  });

  final int evalId;
  final String evalName;

  @override
  State<EvaluationChatPage> createState() => _EvaluationChatPageState();
}

class _EvaluationChatPageState extends State<EvaluationChatPage> {
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _refreshTimer;

  bool _loading = true;
  bool _refreshing = false;
  bool _sending = false;
  String? _err;
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (silent && (_refreshing || _sending)) return;
    if (silent) {
      _refreshing = true;
    } else {
      setState(() {
        _loading = true;
        _err = null;
      });
    }
    try {
      final data = await AuthService.instance.api.evaluationChat(widget.evalId);
      if (!mounted) return;
      final hadMessages = _messages.isNotEmpty;
      final lastId = hadMessages ? _messages.last['id'] : null;
      final nextLastId = data.isNotEmpty ? data.last['id'] : null;
      setState(() {
        _messages = data;
        if (!silent) _err = null;
      });
      if (!silent || nextLastId != lastId || !hadMessages) {
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() => _err = '$e');
    } finally {
      if (silent) {
        _refreshing = false;
      } else if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _send() async {
    final body = _messageCtrl.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    _messageCtrl.clear();
    try {
      final msg = await AuthService.instance.api.sendEvaluationMessage(
        widget.evalId,
        body,
      );
      if (!mounted) return;
      setState(() => _messages = [..._messages, msg]);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _messageCtrl.text = body;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Message failed: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Participant chat'),
        actions: [
          IconButton(
            tooltip: 'Refresh chat',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: GradientBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GlassCard(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppTheme.cyan.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.forum_outlined,
                            color: AppTheme.cyan,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.evalName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'Shared coordination space for this evaluation.',
                                style: TextStyle(color: AppTheme.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_loading) const LinearProgressIndicator(),
                  if (_err != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _err!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Expanded(
                    child: GlassCard(
                      padding: const EdgeInsets.all(12),
                      child:
                          _messages.isEmpty && !_loading
                              ? const Center(
                                child: Text(
                                  'No messages yet. Start the evaluation discussion here.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppTheme.muted),
                                ),
                              )
                              : ListView.separated(
                                controller: _scrollCtrl,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                itemCount: _messages.length,
                                separatorBuilder:
                                    (_, _) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final msg = _messages[index];
                                  final author =
                                      msg['author'] as Map<String, dynamic>? ??
                                      {};
                                  final me = AuthService.instance.currentUser;
                                  final mine = author['id'] == me?['user_id'];
                                  return _MessageBubble(
                                    author: author,
                                    body: '${msg['body'] ?? ''}',
                                    createdAt: '${msg['created_at'] ?? ''}',
                                    mine: mine,
                                  );
                                },
                              ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageCtrl,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            decoration: const InputDecoration(
                              hintText: 'Message participants',
                              prefixIcon: Icon(Icons.chat_bubble_outline),
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _sending ? null : _send,
                          child:
                              _sending
                                  ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.send_outlined),
                        ),
                      ],
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
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.author,
    required this.body,
    required this.createdAt,
    required this.mine,
  });

  final Map<String, dynamic> author;
  final String body;
  final String createdAt;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final name = AnonService.nameFromId(author['id'] as int?);
    final avatar = _absoluteAvatar('${author['avatar'] ?? ''}');
    final bubbleColor =
        mine
            ? AppTheme.cyan.withValues(alpha: .18)
            : AppTheme.elevated.withValues(alpha: .78);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Row(
          mainAxisAlignment:
              mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine) _Avatar(name: name, avatar: avatar),
            if (!mine) const SizedBox(width: 10),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(mine ? 18 : 6),
                    bottomRight: Radius.circular(mine ? 6 : 18),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (createdAt.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            _shortDate(createdAt),
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    SelectableText(body),
                  ],
                ),
              ),
            ),
            if (mine) const SizedBox(width: 10),
            if (mine) _Avatar(name: name, avatar: avatar),
          ],
        ),
      ),
    );
  }

  static String _absoluteAvatar(String value) {
    if (value.isEmpty || value == 'null') return '';
    return apiFileUrl(value);
  }

  static String _shortDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.avatar});

  final String name;
  final String avatar;

  @override
  Widget build(BuildContext context) {
    return UserAvatar(name: name, avatar: avatar, radius: 18, anonymize: true);
  }
}
