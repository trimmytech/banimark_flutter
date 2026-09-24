import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:banimark_flutter/banimark_flutter.dart';

void main() {
  final cfg = BanimarkConfig.laravel('https://app.test/');

  test('the app follows the desk: guest fields, intro and starters', () async {
    final client = MockClient((req) async => http.Response(jsonEncode({
          'color': '#6F04D9',
          'title': 'Support',
          'guest_intro': 'Tell us how to reach you.',
          'guest_fields': [
            {'key': 'name', 'label': 'Your name', 'type': 'text', 'required': true},
            {'key': 'phone', 'label': 'Mobile (WhatsApp)', 'type': 'tel', 'required': false},
          ],
          'starters': ['Where is my order?', 'I need a refund'],
        }), 200));
    final a = await BanimarkAppearance.fetch(cfg, client: client);
    expect(a, isNotNull);
    expect(a!.guestIntro, 'Tell us how to reach you.');
    expect(a.guestFields.map((f) => f.key).toList(), ['name', 'phone']);
    expect(a.guestFields.first.required, isTrue);
    expect(a.guestFields.last.type, 'tel');
    expect(a.starters, ['Where is my order?', 'I need a refund']);
  });

  test('an older desk that sends none of this still works', () async {
    final client = MockClient((req) async => http.Response(jsonEncode({'title': 'Support'}), 200));
    final a = await BanimarkAppearance.fetch(cfg, client: client);
    expect(a!.guestFields, isEmpty);
    expect(a.starters, isEmpty);
    expect(a.guestIntro, isNull);
  });

  test('a phone number travels with the visitor', () {
    const v = BanimarkVisitor(name: 'Ada', email: 'ada@x.test', phone: '+234 800 000 0000');
    expect(v.toJson(), {'name': 'Ada', 'email': 'ada@x.test', 'phone': '+234 800 000 0000'});
    expect(v['phone'], '+234 800 000 0000');
    expect(const BanimarkVisitor().isEmpty, isTrue);
    expect(const BanimarkVisitor(phone: '123').isEmpty, isFalse);
    expect(const BanimarkVisitor(name: 'Ada').toJson(), {'name': 'Ada'});
  });
}
