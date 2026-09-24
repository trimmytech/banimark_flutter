import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// The formatting a chat message may carry - **bold**, *italic*, `code`,
/// fenced code, links, bullet and numbered lists - the same subset the web
/// widget and the staff panel render, so a reply looks the same everywhere.
/// Nothing else is interpreted; a stray `<b>` stays literal text.
class BanimarkMarkdown extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;
  final void Function(Uri uri)? onOpenLink;
  const BanimarkMarkdown({super.key, required this.text, required this.style, required this.linkColor, this.onOpenLink});

  @override
  Widget build(BuildContext context) {
    final blocks = parseBlocks(text);
    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (i > 0) children.add(const SizedBox(height: 8));
      switch (b.kind) {
        case BlockKind.code:
          children.add(Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: style.color!.withValues(alpha: .08), borderRadius: BorderRadius.circular(9)),
            child: Text(b.lines.join('\n'), style: style.copyWith(fontFamily: 'monospace', fontSize: (style.fontSize ?? 15) - 2)),
          ));
        case BlockKind.bullets:
        case BlockKind.numbers:
          for (var n = 0; n < b.lines.length; n++) {
            children.add(Padding(
              padding: EdgeInsets.only(top: n == 0 ? 0 : 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 22, child: Text(b.kind == BlockKind.bullets ? '•' : '${n + 1}.', style: style)),
                Expanded(child: _rich(b.lines[n])),
              ]),
            ));
          }
        case BlockKind.paragraph:
          children.add(_rich(b.lines.join('\n')));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _rich(String line) => Text.rich(TextSpan(children: inlineSpans(line, style, linkColor, onOpenLink)));

  /// Split text into blocks: paragraphs, bullet/number lists, fenced code.
  static List<MdBlock> parseBlocks(String text) {
    final src = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    final out = <MdBlock>[];
    if (src.isEmpty) return out;
    final lines = src.split('\n');
    var i = 0;
    var para = <String>[];
    void flush() {
      if (para.isNotEmpty) {
        out.add(MdBlock(BlockKind.paragraph, List.of(para)));
        para = [];
      }
    }
    while (i < lines.length) {
      final line = lines[i];
      if (line.trimLeft().startsWith('```')) {
        flush();
        final code = <String>[];
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
          code.add(lines[i]);
          i++;
        }
        i++; // closing fence (or end)
        out.add(MdBlock(BlockKind.code, code));
        continue;
      }
      final bullet = RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(line);
      final number = bullet == null ? RegExp(r'^\s*\d+[.)]\s+(.*)$').firstMatch(line) : null;
      if (bullet != null || number != null) {
        flush();
        final kind = bullet != null ? BlockKind.bullets : BlockKind.numbers;
        final items = <String>[];
        while (i < lines.length) {
          final m = kind == BlockKind.bullets ? RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(lines[i]) : RegExp(r'^\s*\d+[.)]\s+(.*)$').firstMatch(lines[i]);
          if (m == null) break;
          items.add(m.group(1)!);
          i++;
        }
        out.add(MdBlock(kind, items));
        continue;
      }
      if (line.trim().isEmpty) {
        flush();
      } else {
        para.add(line);
      }
      i++;
    }
    flush();
    return out;
  }

  /// Inline: **bold**, *italic*, _italic_, `code`, [text](url), bare URLs.
  static List<InlineSpan> inlineSpans(String text, TextStyle base, Color linkColor, void Function(Uri)? onOpenLink) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(`[^`\n]+`)' // 1 code
      r'|(\*\*(?=\S)(.+?)(?<=\S)\*\*)' // 2,3 bold
      r'|((?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?!\w))' // 4,5 italic *
      r'|((?<![\w_])_(?=\S)([^_\n]+?)(?<=\S)_(?!\w))' // 6,7 italic _
      r'|(\[([^\]\n]+)\]\((https?://[^\s)]+|mailto:[^\s)]+)\))' // 8,9,10 link
      r'|((?<![="' "'" r'>/])\bhttps?://[^\s<]+[^\s<.,;:!?)"' "'" r'])', // 11 bare url
    );
    var last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start), style: base));
      if (m.group(1) != null) {
        final code = m.group(1)!;
        spans.add(TextSpan(
          text: code.substring(1, code.length - 1),
          style: base.copyWith(fontFamily: 'monospace', fontSize: (base.fontSize ?? 15) - 2, backgroundColor: base.color!.withValues(alpha: .10)),
        ));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(text: m.group(3), style: base.copyWith(fontWeight: FontWeight.w700)));
      } else if (m.group(5) != null || m.group(7) != null) {
        spans.add(TextSpan(text: m.group(5) ?? m.group(7), style: base.copyWith(fontStyle: FontStyle.italic)));
      } else if (m.group(9) != null) {
        spans.add(_link(m.group(9)!, m.group(10)!, base, linkColor, onOpenLink));
      } else if (m.group(11) != null) {
        spans.add(_link(m.group(11)!, m.group(11)!, base, linkColor, onOpenLink));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last), style: base));
    return spans;
  }

  static InlineSpan _link(String label, String url, TextStyle base, Color color, void Function(Uri)? onOpenLink) {
    final uri = Uri.tryParse(url);
    return TextSpan(
      text: label,
      style: base.copyWith(color: color, decoration: TextDecoration.underline),
      recognizer: uri == null || onOpenLink == null ? null : (TapGestureRecognizer()..onTap = () => onOpenLink(uri)),
    );
  }
}

enum BlockKind { paragraph, bullets, numbers, code }

class MdBlock {
  final BlockKind kind;
  final List<String> lines;
  const MdBlock(this.kind, this.lines);
}
