import 'dart:convert';

import 'package:banimark_flutter/banimark_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Resending is the one thing that must never be lost: the web widget and the
/// shareable chat link mark a failed bubble and put a Retry button on it, and
/// this is the same promise on mobile. Keep the three in step.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cfg = BanimarkConfig.laravel('https://app.test/');

  test('a message the desk could not take stays in the thread, marked, and retry sends it again', () async {
    final bodies = <String>[];
    var failNext = true;
    final client = BanimarkClient(cfg, httpClient: MockClient((req) async {
      bodies.add(req.body);
      if (failNext) {
        failNext = false;
        // exactly what a broken server gives you: HTML, not JSON
        return http.Response('<!doctype html><h1>Server Error</h1>', 500);
      }
      return http.Response(jsonEncode({'ok': true, 'session_id': 'abc', 'reply': 'Got it!', 'mode': 'ai'}), 200);
    }));
    final c = BanimarkController(config: cfg, client: client, storageKey: 'resend_test');

    await c.send('hello 😘');
    final failed = c.messages.single;
    expect(failed.failed, isTrue, reason: 'the bubble has to say it did not arrive');
    expect(failed.pending, isFalse);
    expect(failed.text, 'hello 😘', reason: 'what was typed must still be there to resend');
    expect(c.error, isNotNull);

    await c.retry(failed);
    expect(jsonDecode(bodies[1])['message'], jsonDecode(bodies[0])['message'], reason: 'the retry sends the identical message');
    expect(c.messages.any((m) => m.failed), isFalse);
    expect(c.messages.last.text, 'Got it!');
    expect(c.messages.where((m) => m.isMine).length, 1, reason: 'one message, not a duplicate');
  });

  test('a message that fails on a 422 keeps the reason the desk gave', () async {
    final client = BanimarkClient(cfg, httpClient: MockClient((req) async => http.Response(
        jsonEncode({'ok': false, 'session_id': '', 'reply': '', 'error': 'That message is too long - please shorten it.'}), 422)));
    final c = BanimarkController(config: cfg, client: client, storageKey: 'resend_test2');
    await c.send('x');
    expect(c.messages.single.failed, isTrue);
    expect(c.error, 'That message is too long - please shorten it.');
  });
}
