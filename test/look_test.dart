import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:banimark_flutter/banimark_flutter.dart';

/// The owner's look (Widget page) reaches the app as it reaches the website:
/// header line, away note, logo, corners, spacing and the reply chime.
void main() {
  Future<BanimarkAppearance> fetch(BanimarkConfig cfg, Map<String, dynamic> body) async =>
      (await BanimarkAppearance.fetch(cfg, client: MockClient((_) async => http.Response(jsonEncode(body), 200))))!;

  final laravel = BanimarkConfig.laravel('https://app.test/');
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the look travels: status line, corners, spacing, sound, logo', () async {
    final a = await fetch(laravel, {
      'status_line': 'Usually replies in minutes',
      'corner': 'square',
      'density': 'compact',
      'sound': false,
      'logo_url': 'https://app.test/banimark/widget/logo?v=abc1234567',
    });
    final t = a.applyTo(BanimarkTheme.light);
    expect(t.subtitle, 'Usually replies in minutes');
    expect(t.bubbleRadius, 6);
    expect(t.inputRadius, 6);
    expect(t.compact, isTrue);
    expect(a.sound, isFalse);
    expect(a.logo.toString(), 'https://app.test/banimark/widget/logo?v=abc1234567');
    expect(t.avatar, isNotNull, reason: 'the logo becomes the header avatar');
  });

  test('out of hours the away note wins over the status line, as on the website', () async {
    final a = await fetch(laravel, {'status_line': 'We reply fast', 'away_note': 'Outside our hours - a person is back Monday at 9:00.'});
    expect(a.applyTo(BanimarkTheme.light).subtitle, 'Outside our hours - a person is back Monday at 9:00.');
  });

  test('a standalone desk sends a path; the app resolves it against the endpoint', () async {
    final a = await fetch(BanimarkConfig.standalone('https://shop.test/support'), {'logo_url': '/support/widget/logo?v=1'});
    expect(a.logo.toString(), 'https://shop.test/support/widget/logo?v=1');
    final bad = await fetch(laravel, {'logo_url': 'javascript:alert(1)'});
    expect(bad.logo, isNull, reason: 'only http(s) pictures');
  });

  test('a never-activated desk reports enabled:false; older desks default to true', () async {
    expect((await fetch(laravel, {'enabled': false})).enabled, isFalse);
    expect((await fetch(laravel, {'title': 'Support'})).enabled, isTrue, reason: 'older desks omit the flag');
    expect((await fetch(laravel, {'enabled': true})).enabled, isTrue);
  });

  test('an older desk that sends none of it keeps the theme exactly as it was', () async {
    final a = await fetch(laravel, {'title': 'Support'});
    final t = a.applyTo(BanimarkTheme.light);
    expect(t.subtitle, BanimarkTheme.light.subtitle);
    expect(t.bubbleRadius, BanimarkTheme.light.bubbleRadius);
    expect(t.inputRadius, BanimarkTheme.light.inputRadius);
    expect(t.compact, isFalse);
    expect(t.avatar, isNull);
    expect(a.sound, isTrue, reason: 'the chime stays on unless the owner says otherwise');
    final soft = (await fetch(laravel, {'corner': 'soft'})).applyTo(BanimarkTheme.light);
    expect(soft.bubbleRadius, 12);
  });

  testWidgets('a logo that will not load falls back to the chat glyph', (tester) async {
    final a = await fetch(laravel, {'logo_url': 'https://app.test/banimark/widget/logo?v=1'});
    final t = a.applyTo(BanimarkTheme.light);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: t.avatar!)));
    await tester.pump();
    // test HTTP answers 400 to every image request, so this is the failure path
    expect(find.byIcon(Icons.chat_bubble_rounded), findsOneWidget);
  });

  test('the look is kept, so a chat opened later paints in it from the first frame', () async {
    final cfg = BanimarkConfig.laravel('https://kept.test/');
    expect(BanimarkAppearance.cached(cfg), isNull);
    await fetch(cfg, {'color': '#123456'});
    expect(BanimarkAppearance.cached(cfg)?.primary, const Color(0xFF123456), reason: 'this run');
    expect((await BanimarkAppearance.stored(cfg))?.primary, const Color(0xFF123456), reason: 'the next run, before the network answers');
  });
}
