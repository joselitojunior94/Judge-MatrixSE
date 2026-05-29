import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

const String kApiBaseUrl =
    'https://judgematrixsestudio.experimental-machine94.vps-kinghost.net';

String apiFileUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value == 'null') return '';
  final base =
      kApiBaseUrl.endsWith('/')
          ? kApiBaseUrl.substring(0, kApiBaseUrl.length - 1)
          : kApiBaseUrl;
  final publicBase = Uri.parse(base);
  final incoming = Uri.tryParse(value);
  if (incoming != null && incoming.hasScheme) {
    if (incoming.host == publicBase.host) {
      return publicBase
          .replace(path: incoming.path, query: incoming.query)
          .toString();
    }
    return value;
  }
  final path = value.startsWith('/') ? value : '/$value';
  return '$base$path';
}

/// Low-level REST client.
///
/// Constructed with a current [accessToken].
/// Pass [onTokenExpired] so callers (AuthService) can refresh + rebuild the
/// client when a 401 is received. The callback must return a fresh access
/// token string, or null if refresh failed (triggers logout).
class Api {
  Api(this._access, {this.onTokenExpired});

  String _access;
  final Future<String?> Function()? onTokenExpired;

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------
  Map<String, String> _h([Map<String, String>? extra]) => {
    'Authorization': 'Bearer $_access',
    ...?extra,
  };

  Future<http.Response> _get(Uri uri) async {
    var r = await http.get(uri, headers: _h());
    if (r.statusCode == 401) {
      r = await _retry(r, () => http.get(uri, headers: _h()));
    }
    return r;
  }

  Future<http.Response> _post(Uri uri, {Map<String, dynamic>? body}) async {
    final headers = _h({'Content-Type': 'application/json'});
    var r = await http.post(
      uri,
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (r.statusCode == 401) {
      r = await _retry(
        r,
        () => http.post(
          uri,
          headers: _h({'Content-Type': 'application/json'}),
          body: body != null ? jsonEncode(body) : null,
        ),
      );
    }
    return r;
  }

  /// On 401: ask the caller to refresh. If a new token arrives, update
  /// [_access] and redo the request once. Otherwise re-return the 401.
  Future<http.Response> _retry(
    http.Response original,
    Future<http.Response> Function() redo,
  ) async {
    final fresh = await onTokenExpired?.call();
    if (fresh == null) return original; // refresh failed → caller logs out
    _access = fresh;
    return redo();
  }

  void _require(http.Response r, {int expect = 200}) {
    if (r.statusCode != expect && (expect != 200 || r.statusCode >= 300)) {
      throw Exception('${r.request?.url.path}: ${r.statusCode} ${r.body}');
    }
  }

  // -------------------------------------------------------------------------
  // Auth / profile
  // -------------------------------------------------------------------------
  Future<Map<String, dynamic>> me() async {
    final r = await _get(Uri.parse('$kApiBaseUrl/api/auth/me/'));
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateProfile({
    required Map<String, String> fields,
    Uint8List? avatarBytes,
    String? avatarFilename,
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/api/auth/me/update/');
    http.Response r;
    if (avatarBytes != null) {
      final req = http.MultipartRequest('PATCH', uri)..headers.addAll(_h());
      req.fields.addAll(fields);
      final ext = (avatarFilename ?? '').split('.').last.toLowerCase();
      final subtype = switch (ext) {
        'jpg' || 'jpeg' => 'jpeg',
        'gif' => 'gif',
        'webp' => 'webp',
        _ => 'png',
      };
      req.files.add(
        http.MultipartFile.fromBytes(
          'avatar',
          avatarBytes,
          filename: avatarFilename ?? 'avatar.png',
          contentType: MediaType('image', subtype),
        ),
      );
      final streamed = await req.send();
      r = await http.Response.fromStream(streamed);
    } else {
      r = await http.patch(
        uri,
        headers: _h({'Content-Type': 'application/json'}),
        body: jsonEncode(fields),
      );
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('profile: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> syncPublications({String? orcid}) async {
    final r = await _post(
      Uri.parse('$kApiBaseUrl/api/auth/me/publications/sync/'),
      body: {if (orcid != null) 'orcid': orcid},
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('sync publications: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // -------------------------------------------------------------------------
  // User search (for adding collaborators to evaluations)
  // -------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> userSearch(String query) async {
    final uri = Uri.parse(
      '$kApiBaseUrl/api/users/',
    ).replace(queryParameters: query.isNotEmpty ? {'search': query} : null);
    final r = await _get(uri);
    _require(r);
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> userProfile(int userId) async {
    final r = await _get(Uri.parse('$kApiBaseUrl/api/users/$userId/profile/'));
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> notifications() async {
    final r = await _get(Uri.parse('$kApiBaseUrl/api/notifications/'));
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> markNotificationsRead({List<int> ids = const []}) async {
    final r = await _post(
      Uri.parse('$kApiBaseUrl/api/notifications/read/'),
      body: {'ids': ids},
    );
    _require(r);
  }

  Future<Map<String, dynamic>> friends() async {
    final r = await _get(Uri.parse('$kApiBaseUrl/api/friends/'));
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> followUser({
    int? userId,
    String? username,
  }) async {
    final r = await _post(
      Uri.parse('$kApiBaseUrl/api/friends/invite/'),
      body: {
        if (userId != null) 'user_id': userId,
        if (username != null && username.isNotEmpty) 'username': username,
      },
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('follow user: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> unfollowUser(int userId) async {
    var r = await http.delete(
      Uri.parse('$kApiBaseUrl/api/friends/$userId/unfollow/'),
      headers: _h(),
    );
    if (r.statusCode == 401) {
      final fresh = await onTokenExpired?.call();
      if (fresh != null) {
        _access = fresh;
        r = await http.delete(
          Uri.parse('$kApiBaseUrl/api/friends/$userId/unfollow/'),
          headers: _h(),
        );
      }
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('unfollow user: ${r.statusCode} ${r.body}');
    }
  }

  Future<Map<String, dynamic>> userFollows(int userId) async {
    final r = await _get(Uri.parse('$kApiBaseUrl/api/users/$userId/follows/'));
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> platformRankings() async {
    final r = await _get(Uri.parse('$kApiBaseUrl/api/rankings/platform/'));
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> evaluationRankings(int evalId) async {
    final r = await _get(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/rankings/'),
    );
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // -------------------------------------------------------------------------
  // Datasets
  // -------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getDatasets() async {
    final r = await _get(Uri.parse('$kApiBaseUrl/api/datasets/'));
    _require(r);
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getDataset(int id) async {
    final r = await _get(Uri.parse('$kApiBaseUrl/api/datasets/$id/'));
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> upload({
    required Uint8List bytes,
    required String filename,
    required Map<String, dynamic> meta,
    int? datasetId,
  }) async {
    final uri = Uri.parse(
      datasetId == null
          ? '$kApiBaseUrl/api/datasets/upload-csv/'
          : '$kApiBaseUrl/api/datasets/$datasetId/upload-csv/',
    );
    final req =
        http.MultipartRequest('POST', uri)
          ..headers.addAll(_h())
          ..fields['meta'] = jsonEncode(meta)
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: filename,
              contentType: MediaType('text', 'csv'),
            ),
          );
    final s = await req.send();
    final r = await http.Response.fromStream(s);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('upload: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> saveMap(int ds, int ver, List<Map<String, dynamic>> cols) async {
    final r = await _post(
      Uri.parse('$kApiBaseUrl/api/datasets/$ds/versions/$ver/mapping/'),
      body: {'columns': cols},
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('mapping: ${r.statusCode} ${r.body}');
    }
  }

  Future<Map<String, dynamic>> generateLabelNormalization({
    required int datasetId,
    required String labelColumn,
  }) async {
    final r = await _post(
      Uri.parse(
        '$kApiBaseUrl/api/datasets/$datasetId/llm/label-normalization/',
      ),
      body: {'label_column': labelColumn},
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('label normalization: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> decideLabelNormalization({
    required int proposalId,
    required String status,
    Map<String, String>? mapping,
  }) async {
    final headers = _h({'Content-Type': 'application/json'});
    final body = jsonEncode({
      'status': status,
      if (mapping != null) 'mapping': mapping,
    });
    var r = await http.patch(
      Uri.parse('$kApiBaseUrl/api/llm/label-normalization/$proposalId/'),
      headers: headers,
      body: body,
    );
    if (r.statusCode == 401) {
      final fresh = await onTokenExpired?.call();
      if (fresh != null) {
        _access = fresh;
        r = await http.patch(
          Uri.parse('$kApiBaseUrl/api/llm/label-normalization/$proposalId/'),
          headers: _h({'Content-Type': 'application/json'}),
          body: body,
        );
      }
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception(
        'label normalization decision: ${r.statusCode} ${r.body}',
      );
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // -------------------------------------------------------------------------
  // Evaluations
  // -------------------------------------------------------------------------
  Future<List<dynamic>> evals() async {
    final r = await _get(Uri.parse('$kApiBaseUrl/api/evaluations/'));
    _require(r);
    return jsonDecode(r.body) as List;
  }

  Future<List<Map<String, dynamic>>> publicEvaluations() async {
    final r = await _get(Uri.parse('$kApiBaseUrl/api/evaluations/public/'));
    _require(r);
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> joinPublicEvaluation(
    int evalId,
    String role,
  ) async {
    final r = await _post(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/join/'),
      body: {'role': role},
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('join evaluation: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getEvaluation(int id) async {
    final r = await _get(Uri.parse('$kApiBaseUrl/api/evaluations/$id/'));
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createEval(
    String name,
    int datasetId, {
    List<int> judges = const [],
    List<int> reviewers = const [],
    List<int> viewers = const [],
    String labelingInstructions = '',
    bool allowMultipleLabels = false,
  }) async {
    final r = await _post(
      Uri.parse('$kApiBaseUrl/api/evaluations/'),
      body: {
        'name': name,
        'dataset': datasetId,
        'judges': judges,
        'reviewers': reviewers,
        'viewers': viewers,
        'labeling_instructions': labelingInstructions,
        'allow_multiple_labels': allowMultipleLabels,
      },
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('create eval: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateEvalMembers(
    int evalId, {
    String? name,
    List<int> judges = const [],
    List<int> reviewers = const [],
    List<int> viewers = const [],
    bool? isPublic,
    List<String>? publicJoinRoles,
    String? labelingInstructions,
    bool? allowMultipleLabels,
  }) async {
    final headers = _h({'Content-Type': 'application/json'});
    final body = jsonEncode({
      if (name != null) 'name': name,
      'judges': judges,
      'reviewers': reviewers,
      'viewers': viewers,
      if (isPublic != null) 'is_public': isPublic,
      if (publicJoinRoles != null) 'public_join_roles': publicJoinRoles,
      if (labelingInstructions != null)
        'labeling_instructions': labelingInstructions,
      if (allowMultipleLabels != null)
        'allow_multiple_labels': allowMultipleLabels,
    });
    var r = await http.patch(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/'),
      headers: headers,
      body: body,
    );
    if (r.statusCode == 401) {
      final fresh = await onTokenExpired?.call();
      if (fresh != null) {
        _access = fresh;
        r = await http.patch(
          Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/'),
          headers: _h({'Content-Type': 'application/json'}),
          body: body,
        );
      }
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('updateEvalMembers: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> deleteEval(int evalId) async {
    var r = await http.delete(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/'),
      headers: _h(),
    );
    if (r.statusCode == 401) {
      final fresh = await onTokenExpired?.call();
      if (fresh != null) {
        _access = fresh;
        r = await http.delete(
          Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/'),
          headers: _h(),
        );
      }
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('delete evaluation: ${r.statusCode} ${r.body}');
    }
  }

  Future<Map<String, dynamic>> generateEffortRouting(int evalId) async {
    final r = await _post(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/llm/routing/'),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('effort routing: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> decideEffortRouting({
    required int suggestionId,
    required String status,
  }) async {
    final headers = _h({'Content-Type': 'application/json'});
    final body = jsonEncode({'status': status});
    var r = await http.patch(
      Uri.parse('$kApiBaseUrl/api/llm/routing/$suggestionId/'),
      headers: headers,
      body: body,
    );
    if (r.statusCode == 401) {
      final fresh = await onTokenExpired?.call();
      if (fresh != null) {
        _access = fresh;
        r = await http.patch(
          Uri.parse('$kApiBaseUrl/api/llm/routing/$suggestionId/'),
          headers: _h({'Content-Type': 'application/json'}),
          body: body,
        );
      }
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('effort routing decision: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> codebooks(int evalId) async {
    final r = await _get(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/codebooks/'),
    );
    _require(r);
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> generateCodebook(
    int evalId, {
    bool force = false,
  }) async {
    final r = await _post(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/codebooks/'),
      body: {'force': force},
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('codebook: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateCodebook({
    required int codebookId,
    String? markdown,
    Map<String, dynamic>? content,
    String? status,
  }) async {
    final headers = _h({'Content-Type': 'application/json'});
    final body = jsonEncode({
      if (markdown != null) 'markdown': markdown,
      if (content != null) 'content': content,
      if (status != null) 'status': status,
    });
    var r = await http.patch(
      Uri.parse('$kApiBaseUrl/api/codebooks/$codebookId/'),
      headers: headers,
      body: body,
    );
    if (r.statusCode == 401) {
      final fresh = await onTokenExpired?.call();
      if (fresh != null) {
        _access = fresh;
        r = await http.patch(
          Uri.parse('$kApiBaseUrl/api/codebooks/$codebookId/'),
          headers: _h({'Content-Type': 'application/json'}),
          body: body,
        );
      }
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('update codebook: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // -------------------------------------------------------------------------
  // Items
  // -------------------------------------------------------------------------
  Future<Map<String, dynamic>> items(
    int evalId, {
    int page = 1,
    int pageSize = 25,
  }) async {
    final r = await _get(
      Uri.parse(
        '$kApiBaseUrl/api/evaluations/$evalId/items/?page=$page&page_size=$pageSize',
      ),
    );
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // -------------------------------------------------------------------------
  // Judgments
  // -------------------------------------------------------------------------
  Future<void> judgment(
    int evalId,
    int itemId, {
    required String value,
    List<String>? labels,
    double? confidence,
  }) async {
    final r = await _post(
      Uri.parse(
        '$kApiBaseUrl/api/evaluations/$evalId/items/$itemId/judgments/',
      ),
      body: {
        'value': value,
        if (labels != null) 'labels': labels,
        'confidence': confidence,
      },
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('judgment: ${r.statusCode} ${r.body}');
    }
  }

  // -------------------------------------------------------------------------
  // Reviews
  // -------------------------------------------------------------------------
  Future<void> review(
    int evalId,
    int itemId, {
    String notes = '',
    String acceptedValue = '',
  }) async {
    final r = await _post(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/items/$itemId/reviews/'),
      body: {'notes': notes, 'accepted_value': acceptedValue},
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('review: ${r.statusCode} ${r.body}');
    }
  }

  Future<List<dynamic>> getItemReviews(int evalId, int itemId) async {
    final r = await _get(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/items/$itemId/reviews/'),
    );
    if (r.statusCode == 404) return [];
    _require(r);
    return jsonDecode(r.body) as List;
  }

  Future<List<dynamic>> getItemJudgments(int evalId, int itemId) async {
    final r = await _get(
      Uri.parse(
        '$kApiBaseUrl/api/evaluations/$evalId/items/$itemId/judgments/',
      ),
    );
    if (r.statusCode == 404) return [];
    _require(r);
    return jsonDecode(r.body) as List;
  }

  Future<List<Map<String, dynamic>>> evaluationChat(int evalId) async {
    final r = await _get(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/chat/'),
    );
    _require(r);
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> sendEvaluationMessage(
    int evalId,
    String body,
  ) async {
    final r = await _post(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/chat/'),
      body: {'body': body},
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('chat: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> disagreementDiagnosis(
    int evalId,
    int itemId,
  ) async {
    final r = await _get(
      Uri.parse(
        '$kApiBaseUrl/api/evaluations/$evalId/items/$itemId/llm/disagreement/',
      ),
    );
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> generateDisagreementDiagnosis(
    int evalId,
    int itemId,
  ) async {
    final r = await _post(
      Uri.parse(
        '$kApiBaseUrl/api/evaluations/$evalId/items/$itemId/llm/disagreement/',
      ),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('disagreement diagnosis: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> consistencyFindings({
    required int evalId,
    required int judgeId,
  }) async {
    final r = await _get(
      Uri.parse(
        '$kApiBaseUrl/api/evaluations/$evalId/llm/consistency/?judge_id=$judgeId',
      ),
    );
    _require(r);
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> generateConsistencyAudit({
    required int evalId,
    required int judgeId,
  }) async {
    final r = await _post(
      Uri.parse(
        '$kApiBaseUrl/api/evaluations/$evalId/llm/consistency/?judge_id=$judgeId',
      ),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('consistency audit: ${r.statusCode} ${r.body}');
    }
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> resolveConsistencyFinding({
    required int findingId,
    required String status,
    String feedback = '',
  }) async {
    final headers = _h({'Content-Type': 'application/json'});
    final body = jsonEncode({'status': status, 'feedback': feedback});
    var r = await http.patch(
      Uri.parse('$kApiBaseUrl/api/llm/consistency/$findingId/'),
      headers: headers,
      body: body,
    );
    if (r.statusCode == 401) {
      final fresh = await onTokenExpired?.call();
      if (fresh != null) {
        _access = fresh;
        r = await http.patch(
          Uri.parse('$kApiBaseUrl/api/llm/consistency/$findingId/'),
          headers: _h({'Content-Type': 'application/json'}),
          body: body,
        );
      }
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('resolve consistency: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // -------------------------------------------------------------------------
  // Metrics & Results
  // -------------------------------------------------------------------------
  Future<Map<String, dynamic>> metrics(int evalId) async {
    final r = await _get(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/metrics/'),
    );
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> results(int evalId) async {
    final r = await _get(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/results/'),
    );
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> threatReport(int evalId) async {
    final r = await _get(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/threat-report/'),
    );
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // -------------------------------------------------------------------------
  // Export & closure
  // -------------------------------------------------------------------------
  Future<void> openEval(int evalId) async {
    final r = await _post(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/open/'),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('open: ${r.statusCode} ${r.body}');
    }
  }

  Future<void> closeEval(int evalId) async {
    final r = await _post(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/close/'),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('close: ${r.statusCode} ${r.body}');
    }
  }

  Future<void> freezeEval(int evalId) async {
    final r = await _post(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/freeze/'),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('freeze: ${r.statusCode} ${r.body}');
    }
  }

  /// Returns the raw bytes of the CSV export.
  Future<Uint8List> exportCsv(int evalId) async {
    final r = await _get(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/export/csv/'),
    );
    _require(r);
    return r.bodyBytes;
  }

  /// Returns the decoded JSON of the JSON export.
  Future<Map<String, dynamic>> exportJson(int evalId) async {
    final r = await _get(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/export/json/'),
    );
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // -------------------------------------------------------------------------
  // Phase 8 — LLM Meta-evaluation (read-only, member-gated)
  // Each method returns the raw JSON from the server, which includes
  // llm_meta: {provider, model, prompt_version, duration_ms}.
  // -------------------------------------------------------------------------
  Future<Map<String, dynamic>> metaDisagreement(int evalId) async {
    final r = await _get(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/meta/disagreement/'),
    );
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> metaEffort(int evalId) async {
    final r = await _get(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/meta/effort/'),
    );
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> metaConsistency(int evalId) async {
    final r = await _get(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/meta/consistency/'),
    );
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> metaCodebook(int evalId) async {
    final r = await _get(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/meta/codebook/'),
    );
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> metaValidity(int evalId) async {
    final r = await _get(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/meta/validity/'),
    );
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> metaNormalise(int evalId) async {
    final r = await _get(
      Uri.parse('$kApiBaseUrl/api/evaluations/$evalId/meta/normalise/'),
    );
    _require(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
