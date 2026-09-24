import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:banimark_flutter/banimark_flutter.dart';

/// The floating bubble: unread count (9+), dragging that is remembered,
/// closing that comes back after the owner's minutes (and at once on a reply).
void main() {
  final cfg = BanimarkConfig.laravel('https://app.test/');
  BanimarkController controller({String key = 'lt'}) => BanimarkController(
      config: cfg, storageKey: key, client: BanimarkClient(cfg, httpClient: MockClient((_) async => http.Response(jsonEncode({'ok': true, 'messages': [], 'mode': 'ai'}), 200))));

  Widget app(BanimarkController c, {Duration? reappear, Key? key}) => MaterialApp(
        home: BanimarkLauncher(
          key: key,
          config: cfg,
          controller: c,
          followAdminAppearance: false,
          reappearAfter: reappear,
          child: const Scaffold(body: Center(child: Text('home'))),
        ),
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the badge shows the unread count and says 9+ past nine', (tester) async {
    final c = controller();
    await tester.pumpWidget(app(c));
    await tester.pump();
    expect(find.byKey(BanimarkLauncher.bubbleKey), findsOneWidget);
    expect(find.byKey(BanimarkLauncher.badgeKey), findsNothing, reason: 'no badge at zero');
    c.unread = 3;
    c.notifyListeners();
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    c.unread = 12;
    c.notifyListeners();
    await tester.pump();
    expect(find.text('9+'), findsOneWidget);
    expect(c.active, isFalse, reason: 'with the chat closed the controller polls at the idle pace');
  });

  testWidgets('it can be dragged anywhere and the spot is remembered', (tester) async {
    final c = controller();
    await tester.pumpWidget(app(c));
    await tester.pump();
    final before = tester.getTopLeft(find.byKey(BanimarkLauncher.bubbleKey));
    await tester.drag(find.byKey(BanimarkLauncher.bubbleKey), const Offset(-250, -400));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.byKey(BanimarkLauncher.bubbleKey));
    expect(after.dx, lessThan(before.dx - 200));
    expect(after.dy, lessThan(before.dy - 300));
    final saved = (await SharedPreferences.getInstance()).getString('banimark_launcher_pos');
    expect(saved, isNotNull, reason: 'the spot is stored on the device');

    // a fresh launcher (next app start) picks the same spot up
    await tester.pumpWidget(app(controller(key: 'lt2'), key: const Key('second')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(BanimarkLauncher.bubbleKey)), after);
  });

  testWidgets('it never leaves the screen', (tester) async {
    await tester.pumpWidget(app(controller()));
    await tester.pump();
    await tester.drag(find.byKey(BanimarkLauncher.bubbleKey), const Offset(-5000, -5000));
    await tester.pumpAndSettle();
    final r = tester.getRect(find.byKey(BanimarkLauncher.bubbleKey));
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.top, greaterThanOrEqualTo(0));
  });

  testWidgets('closing hides it; it comes back after the reappear time', (tester) async {
    await tester.pumpWidget(app(controller(), reappear: const Duration(minutes: 5)));
    await tester.pump();
    await tester.tap(find.byKey(BanimarkLauncher.closeKey));
    await tester.pump();
    expect(find.byKey(BanimarkLauncher.bubbleKey), findsNothing);
    expect((await SharedPreferences.getInstance()).getInt('banimark_launcher_hidden_until'), isNotNull, reason: 'a restart honours the same time');
    await tester.pump(const Duration(minutes: 4));
    expect(find.byKey(BanimarkLauncher.bubbleKey), findsNothing);
    await tester.pump(const Duration(minutes: 2));
    expect(find.byKey(BanimarkLauncher.bubbleKey), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getInt('banimark_launcher_hidden_until'), isNull);
  });

  testWidgets('a stored "come back at" time is honoured on the next start', (tester) async {
    SharedPreferences.setMockInitialValues({'banimark_launcher_hidden_until': DateTime.now().add(const Duration(minutes: 3)).millisecondsSinceEpoch});
    await tester.pumpWidget(app(controller(), reappear: const Duration(minutes: 5)));
    await tester.pumpAndSettle();
    expect(find.byKey(BanimarkLauncher.bubbleKey), findsNothing);
    await tester.pump(const Duration(minutes: 4));
    expect(find.byKey(BanimarkLauncher.bubbleKey), findsOneWidget);
  });

  testWidgets('zero minutes = away until the app is opened again, nothing stored', (tester) async {
    await tester.pumpWidget(app(controller(), reappear: Duration.zero));
    await tester.pump();
    await tester.tap(find.byKey(BanimarkLauncher.closeKey));
    await tester.pump(const Duration(hours: 2));
    expect(find.byKey(BanimarkLauncher.bubbleKey), findsNothing);
    expect((await SharedPreferences.getInstance()).getInt('banimark_launcher_hidden_until'), isNull);
  });

  testWidgets('a reply from the team brings a dismissed bubble straight back', (tester) async {
    final c = controller();
    await tester.pumpWidget(app(c, reappear: const Duration(minutes: 30)));
    await tester.pump();
    await tester.tap(find.byKey(BanimarkLauncher.closeKey));
    await tester.pump();
    expect(find.byKey(BanimarkLauncher.bubbleKey), findsNothing);
    c.unread = 1;
    c.notifyListeners();
    await tester.pump();
    expect(find.byKey(BanimarkLauncher.bubbleKey), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('tapping opens the chat, marks it read and polls fast; closing slows it again', (tester) async {
    final c = controller()..unread = 2;
    await tester.pumpWidget(app(c));
    await tester.pump();
    await tester.tap(find.byKey(BanimarkLauncher.bubbleKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.unread, 0);
    expect(c.active, isTrue);
    expect(find.byType(BanimarkChat), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    expect(find.byType(BanimarkChat), findsNothing);
    expect(c.active, isFalse);
  });

  test('the desk\'s intervals and reappear time travel with the look', () async {
    final a = (await BanimarkAppearance.fetch(cfg, client: MockClient((_) async => http.Response(jsonEncode({'poll_seconds': 7, 'poll_idle_seconds': 45, 'launcher_reappear_minutes': 20}), 200))))!;
    expect(a.pollEvery, const Duration(seconds: 7));
    expect(a.idlePollEvery, const Duration(seconds: 45));
    expect(a.reappearAfter, const Duration(minutes: 20));
    final junk = (await BanimarkAppearance.fetch(cfg, client: MockClient((_) async => http.Response(jsonEncode({'poll_idle_seconds': 1, 'launcher_reappear_minutes': 0}), 200))))!;
    expect(junk.idlePollEvery, const Duration(seconds: 10), reason: 'clamped like the desk');
    expect(junk.reappearAfter, Duration.zero);
    final old = (await BanimarkAppearance.fetch(cfg, client: MockClient((_) async => http.Response(jsonEncode({'title': 'Support'}), 200))))!;
    expect(old.pollEvery, isNull);
    expect(old.idlePollEvery, isNull);
    expect(old.reappearAfter, isNull);
  });

  test('the controller polls at the open pace on screen and the idle pace off it', () {
    final c = controller();
    expect(c.pollInterval, const Duration(seconds: 4));
    c.setActive(false);
    expect(c.pollInterval, const Duration(seconds: 30));
    c.setIntervals(open: const Duration(seconds: 7), idle: const Duration(seconds: 45));
    expect(c.pollInterval, const Duration(seconds: 45));
    c.setActive(true);
    expect(c.pollInterval, const Duration(seconds: 7));
  });

  test('unread survives a restart: replies after the last one read count, then reading records it', () async {
    SharedPreferences.setMockInitialValues({'ur': 'a' * 32, 'ur_seen': 5});
    final client = BanimarkClient(cfg, httpClient: MockClient((req) async => http.Response(jsonEncode({
          'ok': true, 'session_id': 'a' * 32, 'mode': 'agent',
          'messages': [
            {'id': 4, 'role': 'user', 'text': 'hi'}, {'id': 5, 'role': 'assistant', 'text': 'hello'},
            {'id': 6, 'role': 'agent', 'text': 'one'}, {'id': 7, 'role': 'agent', 'text': 'two'}, {'id': 8, 'role': 'user', 'text': 'ok'},
          ],
        }), 200)));
    final c = BanimarkController(config: cfg, client: client, storageKey: 'ur');
    await c.init();
    expect(c.unread, 2, reason: 'the two replies after id 5; the visitor\'s own never count');
    c.markRead();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((await SharedPreferences.getInstance()).getInt('ur_seen'), 8);
    c.dispose();

    // a visitor from before this feature has no mark: nothing is shown as new, the mark is set
    SharedPreferences.setMockInitialValues({'ur2': 'a' * 32});
    final c2 = BanimarkController(config: cfg, client: client, storageKey: 'ur2');
    await c2.init();
    expect(c2.unread, 0);
    expect((await SharedPreferences.getInstance()).getInt('ur2_seen'), 8);
    c2.dispose();
  });
}
