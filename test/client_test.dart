import 'dart:convert';

import 'package:banimark_flutter/banimark_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final cfg = BanimarkConfig.laravel('https://app.test/', token: 'tok');

  test('laravel factory builds the three endpoints without a double slash', () {
    expect(cfg.chat.toString(), 'https://app.test/banimark/chat');
    expect(cfg.poll.toString(), 'https://app.test/banimark/chat/poll');
    expect(cfg.history.toString(), 'https://app.test/banimark/chat/history');
    expect(BanimarkConfig.standalone('https://app.test/banimark.php').chat.toString(), 'https://app.test/banimark.php/chat');
  });

  test('send posts message, session, token and visitor, and parses the reply', () async {
    late Map<String, dynamic> sent;
    final client = BanimarkClient(cfg, httpClient: MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      expect(req.url, cfg.chat);
      return http.Response(jsonEncode({'ok': true, 'session_id': 'abc', 'reply': 'Hello Ada', 'mode': 'ai'}), 200);
    }));
    final r = await client.send(message: 'hi', visitor: const BanimarkVisitor(name: 'Ada', email: 'ada@acme.test'));
    expect(sent['message'], 'hi');
    expect(sent['session_id'], '');
    expect(sent['token'], 'tok');
    expect(sent['visitor'], {'name': 'Ada', 'email': 'ada@acme.test'});
    expect(r.ok, isTrue);
    expect(r.sessionId, 'abc');
    expect(r.reply, 'Hello Ada');
    expect(r.mode, BanimarkMode.ai);
  });

  test('poll maps agent replies and the mode', () async {
    final client = BanimarkClient(cfg, httpClient: MockClient((req) async {
      expect(req.url.queryParameters['after'], '7');
      expect(req.url.queryParameters['session_id'], 'abc');
      return http.Response(jsonEncode({'ok': true, 'mode': 'agent', 'messages': [{'id': 8, 'text': 'Agent here'}]}), 200);
    }));
    final r = await client.poll(sessionId: 'abc', afterId: 7);
    expect(r.mode, BanimarkMode.agent);
    expect(r.messages.single.sender, BanimarkSender.agent);
    expect(r.messages.single.id, 8);
  });

  test('history maps user and bot roles', () async {
    final client = BanimarkClient(cfg, httpClient: MockClient((req) async => http.Response(
        jsonEncode({'ok': true, 'mode': 'ai', 'messages': [{'id': 1, 'role': 'user', 'text': 'hi'}, {'id': 2, 'role': 'bot', 'text': 'hello'}]}), 200)));
    final r = await client.history(sessionId: 'abc');
    expect(r.messages.map((m) => m.sender).toList(), [BanimarkSender.user, BanimarkSender.assistant]);
  });

  test('messages carry their attachments, with a token-addressed URL', () async {
    final client = BanimarkClient(cfg, httpClient: MockClient((req) async => http.Response(
        jsonEncode({'ok': true, 'mode': 'agent', 'agent_typing': false, 'messages': [
          {'id': 9, 'text': 'here it is', 'files': [
            {'id': 3, 'token': 'ab12', 'name': 'receipt.pdf', 'mime': 'application/pdf', 'size': 2048, 'is_image': false}
          ]}
        ]}), 200)));
    final r = await client.poll(sessionId: 'abc');
    final f = r.messages.single.files.single;
    expect(f.name, 'receipt.pdf');
    expect(f.isImage, isFalse);
    expect(f.readableSize, '2 KB');
    expect(f.url(cfg).toString(), 'https://app.test/banimark/file/ab12');
    expect(f.url(cfg, download: true).toString(), endsWith('?download=1'));
  });

  test('uploading posts the file and returns the stored attachment', () async {
    late http.BaseRequest sent;
    final client = BanimarkClient(cfg, httpClient: MockClient((req) async {
      sent = req;
      return http.Response(jsonEncode({'ok': true, 'attachment': {'id': 7, 'token': 'cd34', 'name': 'a.png', 'mime': 'image/png', 'size': 12, 'is_image': true}}), 200);
    }));
    final a = await client.upload(sessionId: 'abc', filename: 'a.png', bytes: [1, 2, 3]);
    expect(sent.url.toString(), 'https://app.test/banimark/upload');
    expect(sent.method, 'POST');
    expect(a.id, 7);
    expect(a.isImage, isTrue);

    final bad = BanimarkClient(cfg, httpClient: MockClient((req) async => http.Response(jsonEncode({'ok': false, 'error': 'That kind of file is not accepted here.'}), 422)));
    expect(() => bad.upload(sessionId: 'abc', filename: 'x.php', bytes: [1]), throwsA(isA<BanimarkException>()));
  });

  test('sending passes the attachment ids the desk gave us', () async {
    late Map<String, dynamic> body;
    final client = BanimarkClient(cfg, httpClient: MockClient((req) async {
      body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'ok': true, 'session_id': 'abc', 'reply': '', 'mode': 'agent'}), 200);
    }));
    await client.send(message: '', sessionId: 'abc', attachments: [7, 8]);
    expect(body['attachments'], [7, 8]);
  });

  test('history is paged: before/limit go out, has_more and oldest_id come back', () async {
    late Uri asked;
    final client = BanimarkClient(cfg, httpClient: MockClient((req) async {
      asked = req.url;
      return http.Response(jsonEncode({'ok': true, 'mode': 'ai', 'session_id': 'abc', 'has_more': true, 'oldest_id': 40,
        'messages': [{'id': 40, 'role': 'user', 'text': 'older'}, {'id': 41, 'role': 'bot', 'text': 'reply'}]}), 200);
    }));
    final h = await client.history(sessionId: 'abc', beforeId: 55);
    expect(asked.queryParameters['before'], '55');
    expect(asked.queryParameters['limit'], '15');
    expect(h.hasMore, isTrue);
    expect(h.oldestId, 40);
    expect(h.messages.first.text, 'older');
  });

  test('the controller prepends earlier pages and counts staff replies as unread', () async {
    var calls = 0;
    final client = BanimarkClient(cfg, httpClient: MockClient((req) async {
      if (req.url.path.endsWith('/history')) {
        calls++;
        final before = req.url.queryParameters['before'];
        return http.Response(jsonEncode({'ok': true, 'mode': 'ai', 'session_id': 'abc', 'has_more': before == null, 'oldest_id': before == null ? 20 : 5,
          'messages': before == null
              ? [{'id': 20, 'role': 'user', 'text': 'recent'}]
              : [{'id': 5, 'role': 'bot', 'text': 'ancient'}, {'id': 6, 'role': 'user', 'text': 'old'}]}), 200);
      }
      return http.Response(jsonEncode({'ok': true, 'mode': 'agent', 'agent_typing': false, 'messages': [{'id': 21, 'role': 'agent', 'text': 'Hi from Ada'}]}), 200);
    }));
    SharedPreferences.setMockInitialValues({'paging_test': 'abc'});
    final c = BanimarkController(config: cfg, client: client, storageKey: 'paging_test');
    await c.init();
    expect(c.messages.map((m) => m.text).toList(), ['recent']);
    expect(c.hasMore, isTrue);
    final got = await c.loadEarlier();
    expect(got, 2);
    expect(c.messages.map((m) => m.text).toList(), ['ancient', 'old', 'recent'], reason: 'earlier pages go on top, in order');
    expect(c.hasMore, isFalse);
    expect(await c.loadEarlier(), 0, reason: 'nothing more to fetch');
    expect(calls, 2);

    BanimarkMessage? announced;
    c.onStaffMessage = (m) => announced = m;
    await c.tickForTest();
    expect(c.unread, 1);
    expect(announced?.text, 'Hi from Ada');
    c.markRead();
    expect(c.unread, 0);
    c.dispose();
  });

  test('a 5xx becomes a friendly exception, never a crash', () async {
    final client = BanimarkClient(cfg, httpClient: MockClient((req) async => http.Response('<html>boom</html>', 502)));
    expect(() => client.send(message: 'hi'), throwsA(isA<BanimarkException>()));
  });
}
