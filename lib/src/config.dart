/// Where the desk lives. Banimark exposes three visitor endpoints; the two
/// runtimes mount them at different paths, so use the matching factory.
class BanimarkConfig {
  final Uri chat;
  final Uri poll;
  final Uri history;

  /// Signed visitor token minted by YOUR server with `VisitorToken` - it is
  /// what lets the AI's tools scope rows to this user. Leave null for guests.
  final String? token;

  /// How often to check for human-agent replies once the chat is handed over.
  final Duration pollEvery;

  /// Sent as a heartbeat so staff see "online now" and follow-up emails only
  /// go to visitors who really left.
  final Map<String, String> headers;

  const BanimarkConfig({
    required this.chat,
    required this.poll,
    required this.history,
    this.token,
    this.pollEvery = const Duration(seconds: 4),
    this.headers = const {},
  });

  /// Laravel package: `https://yourapp.com` -> `/banimark/chat` etc.
  factory BanimarkConfig.laravel(String baseUrl,
      {String? token, Duration pollEvery = const Duration(seconds: 4), Map<String, String> headers = const {}}) {
    final b = baseUrl.replaceAll(RegExp(r'/+$'), '');
    return BanimarkConfig(
      chat: Uri.parse('$b/banimark/chat'),
      poll: Uri.parse('$b/banimark/chat/poll'),
      history: Uri.parse('$b/banimark/chat/history'),
      token: token,
      pollEvery: pollEvery,
      headers: headers,
    );
  }

  /// Standalone runtime: the URL of your `banimark.php` entry point, e.g.
  /// `https://yourapp.com/banimark.php` -> `?r=/chat` style routes are handled
  /// by `App::run()`; pass exactly the base the browser widget uses.
  factory BanimarkConfig.standalone(String entryUrl,
      {String? token, Duration pollEvery = const Duration(seconds: 4), Map<String, String> headers = const {}}) {
    final b = entryUrl.replaceAll(RegExp(r'/+$'), '');
    return BanimarkConfig(
      chat: Uri.parse('$b/chat'),
      poll: Uri.parse('$b/chat/poll'),
      history: Uri.parse('$b/chat/history'),
      token: token,
      pollEvery: pollEvery,
      headers: headers,
    );
  }
}

/// Who is chatting. With a [BanimarkConfig.token] the server already knows;
/// for guests these details are stored on the conversation so staff can
/// follow up by email.
class BanimarkVisitor {
  final String? name;
  final String? email;
  final String? phone;
  const BanimarkVisitor({this.name, this.email, this.phone});

  Map<String, String> toJson() => {
        if (name != null && name!.isNotEmpty) 'name': name!,
        if (email != null && email!.isNotEmpty) 'email': email!,
        if (phone != null && phone!.isNotEmpty) 'phone': phone!,
      };

  bool get isEmpty => (name ?? '').isEmpty && (email ?? '').isEmpty && (phone ?? '').isEmpty;

  String? operator [](String key) => switch (key) { 'name' => name, 'email' => email, 'phone' => phone, _ => null };
}

/// One thing a guest is asked for, exactly as the desk's admin panel
/// configured it - so the app puts up the same form as the website widget.
class BanimarkGuestField {
  final String key;
  final String label;
  final String type;
  final bool required;
  const BanimarkGuestField({required this.key, required this.label, this.type = 'text', this.required = false});

  factory BanimarkGuestField.fromJson(Map<String, dynamic> j) => BanimarkGuestField(
        key: (j['key'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        type: (j['type'] ?? 'text').toString(),
        required: j['required'] == true,
      );
}
