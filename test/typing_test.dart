import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:banimark_flutter/banimark_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cfg = BanimarkConfig.laravel('https://app.test/');

  test('the AI dots appear after a pause and stay up for a moment, even for an instant answer', () async {
    final client = BanimarkClient(cfg, httpClient: MockClient((req) async => http.Response(jsonEncode({'ok': true, 'session_id': 'abc', 'reply': 'Hi!', 'mode': 'ai'}), 200)));
    final c = BanimarkController(config: cfg, client: client, storageKey: 'typing_test');
    final seen = <bool>[];
    c.addListener(() => seen.add(c.thinking));
    final sw = Stopwatch()..start();
    final f = c.send('hello');
    await Future.delayed(const Duration(milliseconds: 300));
    expect(c.thinking, isFalse, reason: 'no dots in the first few hundred ms - the message is being "read"');
    await f;
    sw.stop();
    expect(seen.contains(true), isTrue, reason: 'the dots did show');
    expect(c.thinking, isFalse);
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(600 + 900 - 50), reason: 'pause + minimum hold, even though the mock answered instantly');
    expect(c.messages.last.text, 'Hi!');
  });

  test('when a human owns the chat the AI dots never show', () async {
    final client = BanimarkClient(cfg, httpClient: MockClient((req) async => http.Response(jsonEncode({'ok': true, 'session_id': 'abc', 'reply': '', 'mode': 'agent'}), 200)));
    final c = BanimarkController(config: cfg, client: client, storageKey: 'typing_test2')..mode = BanimarkMode.agent;
    final seen = <bool>[];
    c.addListener(() => seen.add(c.thinking));
    await c.send('hello');
    expect(seen.contains(true), isFalse);
  });
}
