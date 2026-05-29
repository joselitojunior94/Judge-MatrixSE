import 'package:flutter/material.dart';

import '../service/auth/auth_service.dart';

/// A searchable chip-input that lets you pick collaborators by username.
///
/// Call [UserPicker] with a label and an [onChanged] callback that receives
/// the list of selected user IDs.
class UserPicker extends StatefulWidget {
  const UserPicker({
    super.key,
    required this.label,
    required this.onChanged,
    this.initialUsers = const [],
  });

  final String label;
  final void Function(List<int> ids) onChanged;
  final List<Map<String, dynamic>> initialUsers;

  @override
  State<UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<UserPicker> {
  final _ctrl   = TextEditingController();
  final _focus  = FocusNode();
  List<Map<String, dynamic>> _selected = [];
  List<Map<String, dynamic>> _results  = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _selected = List<Map<String, dynamic>>.from(widget.initialUsers);
    _ctrl.addListener(_onTyped);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTyped);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _onTyped() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) { setState(() => _results = []); return; }
    setState(() => _searching = true);
    try {
      final res = await AuthService.instance.api.userSearch(q);
      // exclude already-selected
      final selIds = _selected.map((u) => u['id']).toSet();
      setState(() => _results = res.where((u) => !selIds.contains(u['id'])).toList());
    } catch (_) {
      setState(() => _results = []);
    } finally {
      setState(() => _searching = false);
    }
  }

  void _add(Map<String, dynamic> user) {
    setState(() {
      _selected.add(user);
      _results.remove(user);
      _ctrl.clear();
    });
    widget.onChanged(_selected.map((u) => u['id'] as int).toList());
  }

  void _remove(Map<String, dynamic> user) {
    setState(() => _selected.remove(user));
    widget.onChanged(_selected.map((u) => u['id'] as int).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),

      // Selected chips
      if (_selected.isNotEmpty)
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: _selected.map((u) => Chip(
            label: Text(u['username'] as String),
            onDeleted: () => _remove(u),
          )).toList(),
        ),

      if (_selected.isNotEmpty) const SizedBox(height: 6),

      // Search input
      TextField(
        controller: _ctrl,
        focusNode: _focus,
        decoration: InputDecoration(
          hintText: 'Search by username…',
          prefixIcon: const Icon(Icons.person_search_outlined),
          suffixIcon: _searching
              ? const SizedBox(
                  width: 18, height: 18,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ))
              : null,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),

      // Dropdown results
      if (_results.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: _results.take(6).map((u) => ListTile(
              dense: true,
              leading: const Icon(Icons.person_outline, size: 18),
              title: Text(u['username'] as String),
              subtitle: (u['display_name'] as String?) != null &&
                      u['display_name'] != u['username']
                  ? Text(u['display_name'] as String)
                  : null,
              onTap: () => _add(u),
            )).toList(),
          ),
        ),
    ]);
  }
}
