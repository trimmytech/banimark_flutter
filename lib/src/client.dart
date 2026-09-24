import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

/// Thin, dependency-light client for the three visitor endpoints. Use it
/// directly if you build your own UI; [BanimarkChat] uses it underneath.
class BanimarkClient {
  final BanimarkConfig config;
  final http.Client _http;

  BanimarkClient(this.config, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        ...config.headers,
      };

  /// Send a visitor message. An empty [sessionId] starts a new conversation;
  /// the returned [BanimarkReply.sessionId] must be stored and reused.
  Future<BanimarkReply> send({required String message, String sessionId = '', BanimarkVisitor? visitor, List<int> attachments = const []}) async {
    final res = await _http.post(
      config.chat,
      headers: _headers,
      body: jsonEncode({
        'message': message,
        'session_id': sessionId,
        'token': config.token ?? '',
        'visitor': visitor?.toJson() ?? {},
        'attachments': attachments,
      }),
    );
    final body = _decode(res);
    final reply = BanimarkReply.fromJson(body);
    if (!reply.ok && res.statusCode >= 500) {
      throw BanimarkException(reply.error ?? 'The support desk is unavailable right now.');
    }
    return reply;
  }

  /// Human-agent replies newer than [afterId]. Doubles as the presence
  /// heartbeat, so call it on the configured interval while the screen is open.
  Future<({BanimarkMode mode, List<BanimarkMessage> messages, bool agentTyping})> poll({required String sessionId, int afterId = 0, bool typing = false}) async {
    final uri = config.poll.replace(queryParameters: {
      ...config.poll.queryParameters,
      'session_id': sessionId,
      'token': config.token ?? '',
      'after': '$afterId',
      if (typing) 'typing': '1',
    });
    final body = _decode(await _http.get(uri, headers: _headers));
    final msgs = ((body['messages'] as List?) ?? const [])
        .map((m) => BanimarkMessage(
              id: (m['id'] as num?)?.toInt() ?? 0,
              sender: BanimarkSender.agent,
              text: (m['text'] ?? '').toString(),
              at: DateTime.now(),
              files: _files(m['files']),
            ))
        .toList();
    return (mode: modeFrom(body['mode']?.toString()), messages: msgs, agentTyping: body['agent_typing'] == true);
  }

  /// Replay an earlier conversation (the visitor's own messages and the
  /// replies they saw - never the desk's internals).
  /// The last [limit] messages, or the page before [beforeId]. `hasMore` says
  /// whether an older page exists.
  Future<({BanimarkMode mode, List<BanimarkMessage> messages, String sessionId, bool hasMore, int oldestId})> history(
      {required String sessionId, int beforeId = 0, int limit = 15}) async {
    final uri = config.history.replace(queryParameters: {
      ...config.history.queryParameters,
      'session_id': sessionId,
      'token': config.token ?? '',
      if (beforeId > 0) 'before': '$beforeId',
      'limit': '$limit',
    });
    final body = _decode(await _http.get(uri, headers: _headers));
    final msgs = ((body['messages'] as List?) ?? const [])
        .map((m) => BanimarkMessage(
              id: (m['id'] as num?)?.toInt() ?? 0,
              sender: m['role'] == 'user'
                  ? BanimarkSender.user
                  : (m['role'] == 'agent' ? BanimarkSender.agent : BanimarkSender.assistant),
              text: (m['text'] ?? '').toString(),
              at: DateTime.now(),
              files: _files(m['files']),
            ))
        .toList();
    return (
      mode: modeFrom(body['mode']?.toString()),
      messages: msgs,
      sessionId: (body['session_id'] ?? sessionId).toString(),
      hasMore: body['has_more'] == true,
      oldestId: (body['oldest_id'] as num?)?.toInt() ?? 0,
    );
  }

  /// The visitor deletes their conversation. Soft on the desk: it disappears
  /// for the visitor at once, the team keeps it until it is erased (30 days
  /// by default, or never if they choose to keep it). True when the desk
  /// accepted it - including "there was nothing to delete".
  Future<bool> deleteConversation({required String sessionId}) async {
    final res = await _http.post(
      Uri.parse('${config.chat}/delete'),
      headers: _headers,
      body: jsonEncode({'session_id': sessionId, 'token': config.token ?? ''}),
    );
    return _decode(res)['ok'] == true;
  }

  /// Send a file. It is stored immediately and returned with an id; pass that
  /// id to [send] to attach it to the next message.
  Future<BanimarkAttachment> upload({required String sessionId, required String filename, required List<int> bytes}) async {
    final base = config.chat.toString().replaceFirst(RegExp(r'/chat$'), '');
    final req = http.MultipartRequest('POST', Uri.parse('$base/upload'))
      ..fields['session_id'] = sessionId
      ..fields['token'] = config.token ?? ''
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    config.headers.forEach((k, v) => req.headers[k] = v);
    final res = await http.Response.fromStream(await _http.send(req));
    final body = _decode(res);
    if (body['ok'] != true || body['attachment'] == null) {
      throw BanimarkException((body['error'] ?? 'That file could not be sent.').toString());
    }
    return BanimarkAttachment.fromJson(Map<String, dynamic>.from(body['attachment'] as Map));
  }

  static List<BanimarkAttachment> _files(dynamic raw) => ((raw as List?) ?? const [])
      .map((f) => BanimarkAttachment.fromJson(Map<String, dynamic>.from(f as Map)))
      .toList();

  Map<String, dynamic> _decode(http.Response res) {
    try {
      final j = jsonDecode(res.body);
      if (j is Map<String, dynamic>) return j;
    } catch (_) {}
    throw BanimarkException(res.statusCode >= 500 ? 'The support desk is unavailable right now.' : 'Unexpected reply from the support desk.');
  }

  void close() => _http.close();
}
