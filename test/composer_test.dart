import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:banimark_flutter/banimark_flutter.dart';

/// The composer: stays above the keyboard, takes several lines, and the send
/// button never spins (the typing dots already say a reply is coming).
void main() {
  final cfg = BanimarkConfig.laravel('https://app.test/');

  Future<BanimarkController> ready(WidgetTester tester, String key) async {
    SharedPreferences.setMockInitialValues({});
    final c = BanimarkController(
      config: cfg,
      storageKey: key,
      client: BanimarkClient(cfg, httpClient: MockClient((_) async => http.Response(jsonEncode({'ok': true, 'session_id': 's', 'messages': [], 'mode': 'ai'}), 200))),
    );
    await tester.runAsync(c.init);
    return c;
  }

  // a sheet, not a Scaffold: nothing else lifts the chat above the keyboard
  Widget sheet(BanimarkController c) =>
      MaterialApp(home: Material(child: BanimarkChat(config: cfg, controller: c, askGuestDetails: false)));

  testWidgets('the message box sits above the keyboard', (tester) async {
    final c = await ready(tester, 'ct1');
    await tester.pumpWidget(sheet(c));
    final field = find.byType(TextField);
    final before = tester.getBottomLeft(field).dy;

    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    final keyboardTop = tester.view.physicalSize.height / tester.view.devicePixelRatio - 900 / tester.view.devicePixelRatio;
    expect(tester.getBottomLeft(field).dy, lessThan(before));
    expect(tester.getBottomLeft(field).dy, lessThanOrEqualTo(keyboardTop));
  });

  testWidgets('the box takes several lines; Enter adds one instead of sending', (tester) async {
    final c = await ready(tester, 'ct2');
    await tester.pumpWidget(sheet(c));
    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.keyboardType, TextInputType.multiline);
    expect(tf.textInputAction, TextInputAction.newline);
    expect(tf.maxLines, greaterThan(1));
    expect(tf.onSubmitted, isNull);
  });

  testWidgets('while the AI is thinking the send button shows no spinner', (tester) async {
    final c = await ready(tester, 'ct3');
    c.thinking = true;
    await tester.pumpWidget(sheet(c));
    final send = find.byKey(const Key('banimark-send'));
    expect(find.descendant(of: send, matching: find.byType(CircularProgressIndicator)), findsNothing);
    expect(find.descendant(of: send, matching: find.byType(Icon)), findsOneWidget);
  });
}
