import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// One spot the first-run tour points at.
class BanimarkTourStep {
  /// Stored once seen, so each spot is explained once per device.
  final String id;
  final GlobalKey target;
  final String text;
  const BanimarkTourStep({required this.id, required this.target, required this.text});
}

/// Which tour spots this device has already seen. A spot that is not on screen
/// yet (the bin, before there is a conversation) waits for its turn.
class BanimarkTourMemory {
  final String storageKey;
  const BanimarkTourMemory(this.storageKey);

  Future<Set<String>> seen() async {
    try {
      return ((await SharedPreferences.getInstance()).getStringList(storageKey) ?? const []).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> markSeen(Iterable<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = {...(prefs.getStringList(storageKey) ?? const <String>[]), ...ids};
      await prefs.setStringList(storageKey, all.toList());
    } catch (_) {}
  }

  /// Show the whole tour again (a "How does this work?" button, or testing).
  Future<void> reset() async {
    try {
      await (await SharedPreferences.getInstance()).remove(storageKey);
    } catch (_) {}
  }
}

/// Dims the screen, cuts a hole around each spot in turn and explains it.
/// Tapping anywhere moves on; [onFinish] gets whether it was skipped.
class BanimarkTourOverlay extends StatefulWidget {
  final List<BanimarkTourStep> steps;
  final BanimarkTheme theme;
  final void Function(bool skipped) onFinish;
  const BanimarkTourOverlay({super.key, required this.steps, required this.theme, required this.onFinish});

  static const Key nextKey = Key('banimark-tour-next');
  static const Key skipKey = Key('banimark-tour-skip');

  @override
  State<BanimarkTourOverlay> createState() => _BanimarkTourOverlayState();
}

class _BanimarkTourOverlayState extends State<BanimarkTourOverlay> {
  int _i = 0;

  void _next() {
    // a spot that left the screen in the meantime is passed over
    var n = _i + 1;
    while (n < widget.steps.length && _rect(widget.steps[n]) == null) {
      n++;
    }
    if (n >= widget.steps.length) {
      widget.onFinish(false);
    } else {
      setState(() => _i = n);
    }
  }

  Rect? _rect(BanimarkTourStep s) {
    final box = s.target.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final overlay = context.findRenderObject();
    final origin = overlay is RenderBox ? overlay.localToGlobal(Offset.zero) : Offset.zero;
    return (box.localToGlobal(Offset.zero) - origin) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final step = widget.steps[_i];
    final last = _i == widget.steps.length - 1;
    final hole = _rect(step)?.inflate(6);
    return LayoutBuilder(builder: (context, box) {
      // the tip sits on whichever side of the spot has more room
      final below = hole == null || hole.center.dy < box.maxHeight / 2;
      final card = Material(
        color: t.surface,
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(step.text, style: TextStyle(color: t.text, fontSize: 14.5, height: 1.35)),
            const SizedBox(height: 4),
            Row(children: [
              Text('${_i + 1}/${widget.steps.length}', style: TextStyle(color: t.muted, fontSize: 12)),
              const Spacer(),
              if (!last)
                TextButton(key: BanimarkTourOverlay.skipKey, onPressed: () => widget.onFinish(true),
                    style: TextButton.styleFrom(foregroundColor: t.muted), child: Text(t.tourSkip)),
              TextButton(key: BanimarkTourOverlay.nextKey, onPressed: _next,
                  style: TextButton.styleFrom(foregroundColor: t.primary),
                  child: Text(last ? t.tourDone : t.tourNext, style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
          ]),
        ),
      );
      return Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _next,
            child: CustomPaint(painter: _Scrim(hole: hole, radius: 14)),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: below ? (hole?.bottom ?? box.maxHeight / 2) + 12 : null,
          bottom: below ? null : box.maxHeight - hole.top + 12,
          child: SafeArea(top: below, bottom: !below, child: card),
        ),
      ]);
    });
  }
}

class _Scrim extends CustomPainter {
  final Rect? hole;
  final double radius;
  _Scrim({required this.hole, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final all = Path()..addRect(Offset.zero & size);
    final h = hole;
    final shape = h == null ? all : Path.combine(PathOperation.difference, all, Path()..addRRect(RRect.fromRectAndRadius(h, Radius.circular(radius))));
    canvas.drawPath(shape, Paint()..color = const Color(0xB3000000));
    if (h != null) {
      canvas.drawRRect(RRect.fromRectAndRadius(h, Radius.circular(radius)),
          Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.white.withValues(alpha: .9));
    }
  }

  @override
  bool shouldRepaint(_Scrim old) => old.hole != hole;
}
