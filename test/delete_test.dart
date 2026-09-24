import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:banimark_flutter/banimark_flutter.dart';

/// The visitor deletes their conversation from the app, as on the website.
void main() {
  final cfg = BanimarkConfig.laravel('https://app.test/');
  final sid = 'a' * 32;

  MockClient desk(List<http.Request> seen, {bool ok = true}) => MockClient((req) async {
        seen.add(req);
        if (req.url.path.endsWith('/chat/delete')) return http.Response(jsonEncode({'ok': ok, if (!ok) 'error': 'nope'}), ok ? 200 : 422);
        if (req.url.path.endsWith('/chat/history')) {
          return http.Response(jsonEncode({'ok': true, 'session_id': sid, 'mode': 'ai', 'messages': [
            {'id': 1, 'role': 'user', 'text': 'Where is my order?'},
            {'id': 2, 'role': 'bot', 'text': 'On its way!'},
          ]}), 200);
        }
        return http.Response(jsonEncode({'ok': true, 'messages': [], 'mode': 'ai'}), 200);
      });

  test('deleting posts to <chat>/delete and the device starts over', () async {
    SharedPreferences.setMockInitialValues({'dt': sid, 'dt_seen': 2});
    final seen = <http.Request>[];
    final c = BanimarkController(config: cfg, client: BanimarkClient(cfg, httpClient: desk(seen)), storageKey: 'dt');
    await c.init();
    expect(c.messages, hasLength(2));
    expect(await c.deleteConversation(), isTrue);
    final del = seen.firstWhere((r) => r.url.path.endsWith('/chat/delete'));
    expect(del.url.toString(), 'https://app.test/banimark/chat/delete');
    expect(jsonDecode(del.body)['session_id'], sid);
    expect(c.messages, isEmpty);
    expect(c.sessionId, isEmpty);
    expect(c.cleared, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('dt'), isNull, reason: 'the device forgets the conversation');
    expect(prefs.getInt('dt_seen'), isNull);
    c.dispose();
  });

  test('a desk that refuses keeps the thread and says why', () async {
    SharedPreferences.setMockInitialValues({'dt2': sid});
    final c = BanimarkController(config: cfg, client: BanimarkClient(cfg, httpClient: desk([], ok: false)), storageKey: 'dt2');
    await c.init();
    expect(await c.deleteConversation(), isFalse);
    expect(c.messages, hasLength(2));
    expect(c.sessionId, sid);
    expect(c.error, isNotNull);
    c.dispose();
  });

  test('a desk without the route (older, or a stale route cache) says so, not "try again"', () async {
    SharedPreferences.setMockInitialValues({'dt5': sid});
    final c = BanimarkController(config: cfg, storageKey: 'dt5', client: BanimarkClient(cfg, httpClient: MockClient((req) async {
      if (req.url.path.endsWith('/chat/delete')) return http.Response(jsonEncode({'message': 'The route banimark/chat/delete could not be found.'}), 404);
      return http.Response(jsonEncode({'ok': true, 'session_id': sid, 'messages': [], 'mode': 'ai'}), 200);
    })));
    await c.init();
    expect(await c.deleteConversation(), isFalse);
    expect(c.error, contains('not available on this support desk yet'));
    expect(c.sessionId, sid, reason: 'nothing was deleted, so nothing is forgotten');
    c.dispose();
  });

  testWidgets('the bin asks first, then clears the chat', (tester) async {
    SharedPreferences.setMockInitialValues({'dt3': sid});
    final c = BanimarkController(config: cfg, client: BanimarkClient(cfg, httpClient: desk([])), storageKey: 'dt3');
    await tester.runAsync(c.init);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BanimarkChat(config: cfg, controller: c, askGuestDetails: false))));
    await tester.pump();
    expect(find.text('On its way!'), findsOneWidget);
    await tester.tap(find.byKey(const Key('banimark-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this conversation?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('On its way!'), findsOneWidget, reason: 'cancel changes nothing');

    await tester.tap(find.byKey(const Key('banimark-delete')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('banimark-delete-confirm')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('On its way!'), findsNothing);
    expect(find.byKey(const Key('banimark-deleted')), findsOneWidget);
    expect(find.byKey(const Key('banimark-delete')), findsNothing, reason: 'nothing left to delete');
  });

  testWidgets('no conversation yet: no bin', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = BanimarkController(config: cfg, client: BanimarkClient(cfg, httpClient: desk([])), storageKey: 'dt4');
    await tester.runAsync(c.init);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BanimarkChat(config: cfg, controller: c, askGuestDetails: false))));
    await tester.pump();
    expect(find.byKey(const Key('banimark-delete')), findsNothing);
  });
}
