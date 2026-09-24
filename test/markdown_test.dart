import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:banimark_flutter/banimark_flutter.dart';

void main() {
  const base = TextStyle(fontSize: 15, color: Colors.black);
  String plain(List<InlineSpan> spans) => spans.map((s) => (s as TextSpan).text).join('|');

  test('blocks: paragraphs, bullets, numbers, fenced code', () {
    final b = BanimarkMarkdown.parseBlocks('Steps:\n- one\n- two\n\n1. first\n2) second\n```\nSELECT 1\n```\ntail');
    expect(b.map((x) => x.kind).toList(), [BlockKind.paragraph, BlockKind.bullets, BlockKind.numbers, BlockKind.code, BlockKind.paragraph]);
    expect(b[1].lines, ['one', 'two']);
    expect(b[2].lines, ['first', 'second']);
    expect(b[3].lines, ['SELECT 1']);
  });

  test('inline: bold, italic, code, links - and nothing else', () {
    final spans = BanimarkMarkdown.inlineSpans('a **b** and *c* and `d` and [e](https://e.test) https://f.test/x.', base, Colors.blue, null);
    expect(plain(spans), 'a |b| and |c| and |d| and |e| |https://f.test/x|.');
    expect((spans[1] as TextSpan).style!.fontWeight, FontWeight.w700);
    expect((spans[3] as TextSpan).style!.fontStyle, FontStyle.italic);
    expect((spans[5] as TextSpan).style!.fontFamily, 'monospace');
    expect((spans[7] as TextSpan).style!.decoration, TextDecoration.underline);
    // a javascript: "link" and raw HTML stay literal text
    final bad = BanimarkMarkdown.inlineSpans('[x](javascript:alert(1)) <b>y</b> snake_case', base, Colors.blue, null);
    expect(plain(bad), '[x](javascript:alert(1)) <b>y</b> snake_case');
  });

  test('links call back with the URI', () {
    Uri? opened;
    final spans = BanimarkMarkdown.inlineSpans('see [docs](https://d.test/p?q=1)', base, Colors.blue, (u) => opened = u);
    final link = spans[1] as TextSpan;
    (link.recognizer as dynamic).onTap();
    expect(opened.toString(), 'https://d.test/p?q=1');
  });

  testWidgets('renders inside a widget tree', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BanimarkMarkdown(text: 'Hi **there**\n- a\n- b', style: base, linkColor: Colors.blue))));
    expect(find.textContaining('Hi'), findsOneWidget);
    expect(find.text('•'), findsNWidgets(2));
  });
}
