/// Anonymisation layer for the evaluation review period.
///
/// Assigns stable "User N" labels to every user encountered during the session.
/// Numbers are sequential in first-seen order — the same ID always produces
/// the same label within one app session.
///
/// Toggle [enabled] to false to restore real names/avatars everywhere.
class AnonService {
  AnonService._();

  /// Set to false to disable all anonymisation globally.
  static const bool enabled = true;

  static final _idMap  = <int, int>{};
  static final _strMap = <String, int>{};
  static var _counter  = 0;

  /// Returns "User N" for a numeric user ID.
  static String nameFromId(int? userId) {
    if (!enabled || userId == null) return '?';
    final n = _idMap.putIfAbsent(userId, () => ++_counter);
    return 'User $n';
  }

  /// Returns "User N" for a username string (used where only the string is available).
  static String nameFromUsername(String? username) {
    if (!enabled || username == null || username.isEmpty) return 'User ?';
    final n = _strMap.putIfAbsent(username, () => ++_counter);
    return 'User $n';
  }

  /// Replaces every username token in a comma-separated string
  /// (e.g. the 'judges' field from the metrics endpoint).
  static String anonymiseJudgeList(String raw) {
    if (!enabled || raw.isEmpty) return raw;
    final cleaned = raw.replaceAll(RegExp(r'[\[\]]'), '');
    final parts = cleaned.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
    return parts.map(nameFromUsername).join(', ');
  }
}
