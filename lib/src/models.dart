import 'config.dart';

enum BanimarkSender { user, assistant, agent }

/// Who owns the conversation right now: the AI, a human agent, or nobody
/// (closed by staff).
enum BanimarkMode { ai, agent, closed }

BanimarkMode modeFrom(String? s) {
  switch (s) {
    case 'agent':
      return BanimarkMode.agent;
    case 'closed':
      return BanimarkMode.closed;
    default:
      return BanimarkMode.ai;
  }
}

/// A file shared in the chat, by either side.
class BanimarkAttachment {
  final int id;
  final String token;
  final String name;
  final String mime;
  final int size;
  final bool isImage;
  const BanimarkAttachment({this.id = 0, required this.token, required this.name, this.mime = '', this.size = 0, this.isImage = false});

  factory BanimarkAttachment.fromJson(Map<String, dynamic> j) => BanimarkAttachment(
        id: (j['id'] as num?)?.toInt() ?? 0,
        token: (j['token'] ?? '').toString(),
        name: (j['name'] ?? 'file').toString(),
        mime: (j['mime'] ?? '').toString(),
        size: (j['size'] as num?)?.toInt() ?? 0,
        isImage: j['is_image'] == true,
      );

  /// Where to fetch it: the token in the path is the permission.
  Uri url(BanimarkConfig config, {bool download = false}) {
    final base = config.chat.toString().replaceFirst(RegExp(r'/chat$'), '');
    return Uri.parse('$base/file/$token${download ? '?download=1' : ''}');
  }

  String get readableSize => size <= 0
      ? ''
      : size < 1024
          ? '$size B'
          : size < 1048576
              ? '${(size / 1024).round()} KB'
              : '${(size / 1048576).toStringAsFixed(1)} MB';
}

class BanimarkMessage {
  /// Server id for replies; local messages get negative ids until echoed.
  final int id;
  final BanimarkSender sender;
  final String text;
  final DateTime at;
  final bool pending;
  final bool failed;
  final List<BanimarkAttachment> files;

  const BanimarkMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.at,
    this.pending = false,
    this.failed = false,
    this.files = const [],
  });

  BanimarkMessage copyWith({int? id, bool? pending, bool? failed, List<BanimarkAttachment>? files}) => BanimarkMessage(
        id: id ?? this.id,
        sender: sender,
        text: text,
        at: at,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
        files: files ?? this.files,
      );

  bool get isMine => sender == BanimarkSender.user;
}

/// The chat endpoint's answer: `{ok, session_id, reply, mode, error}`.
class BanimarkReply {
  final bool ok;
  final String sessionId;
  final String reply;
  final BanimarkMode mode;
  final String? error;
  const BanimarkReply({required this.ok, required this.sessionId, required this.reply, required this.mode, this.error});

  factory BanimarkReply.fromJson(Map<String, dynamic> j) => BanimarkReply(
        ok: j['ok'] == true,
        sessionId: (j['session_id'] ?? '').toString(),
        reply: (j['reply'] ?? '').toString(),
        mode: modeFrom(j['mode']?.toString()),
        error: j['error']?.toString(),
      );
}

class BanimarkException implements Exception {
  final String message;
  const BanimarkException(this.message);
  @override
  String toString() => message;
}
