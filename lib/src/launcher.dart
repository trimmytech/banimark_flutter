import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appearance.dart';
import 'chat_widget.dart';
import 'config.dart';
import 'controller.dart';
import 'theme.dart';

/// A floating chat bubble over your app - the website widget's launcher, in
/// Flutter. Wrap a screen (or the whole app via `MaterialApp.builder`):
///
/// ```dart
/// BanimarkLauncher(
///   config: BanimarkConfig.laravel('https://yourapp.com'),
///   child: MyHomeScreen(),
/// )
/// ```
///
/// What it does on its own:
///  * shows how many replies from your team are unread (9+ past nine), polling
///    at the desk's "while closed" interval so a closed chat still hears a human;
///  * can be dragged anywhere; the spot is remembered on the device;
///  * can be closed with its small ×; it comes back after the desk's
///    "bring it back after" minutes (or [reappearAfter]), and straight away
///    when a reply from your team arrives;
///  * stays hidden entirely on a desk that is not activated yet.
///
/// Tapping it opens [BanimarkChat] in a bottom sheet; pass [onOpen] to open it
/// your own way (a route, a dialog) - the same [BanimarkController] keeps the
/// thread and the unread count in one place.
class BanimarkLauncher extends StatefulWidget {
  final Widget child;
  final BanimarkConfig config;
  final BanimarkVisitor? visitor;
  final BanimarkTheme? theme;
  final ThemeMode themeMode;

  /// Bring your own controller (e.g. one shared with a chat route).
  final BanimarkController? controller;

  /// Read the desk's Widget page: accent colour, intervals, reappear time,
  /// and whether the desk is live at all.
  final bool followAdminAppearance;

  /// Open the chat your own way. Default: a bottom sheet with [BanimarkChat].
  final void Function(BuildContext context, BanimarkController controller)? onOpen;

  /// Override the desk's "bring it back after" setting. [Duration.zero] = only
  /// when the app is opened again.
  final Duration? reappearAfter;

  /// Override the desk's "while closed, check every" setting.
  final Duration? idlePollEvery;

  /// Where it sits until the visitor drags it somewhere else.
  final Alignment initialAlignment;
  final EdgeInsets margin;
  final double size;

  /// Show the small × that lets the visitor put it away.
  final bool dismissible;

  /// Draw your own bubble (the badge and the × are added around it).
  final Widget Function(BuildContext context, int unread)? bubbleBuilder;

  /// Device storage key for the spot and the "come back at" time.
  final String storageKey;

  // passed through to the default BanimarkChat
  final bool askGuestDetails;
  final bool emoji;
  final bool attachments;
  final void Function(Uri uri)? onOpenLink;

  const BanimarkLauncher({
    super.key,
    required this.config,
    required this.child,
    this.visitor,
    this.theme,
    this.themeMode = ThemeMode.system,
    this.controller,
    this.followAdminAppearance = true,
    this.onOpen,
    this.reappearAfter,
    this.idlePollEvery,
    this.initialAlignment = Alignment.bottomRight,
    this.margin = const EdgeInsets.all(16),
    this.size = 56,
    this.dismissible = true,
    this.bubbleBuilder,
    this.storageKey = 'banimark_launcher',
    this.askGuestDetails = true,
    this.emoji = true,
    this.attachments = true,
    this.onOpenLink,
  });

  static const Key bubbleKey = Key('banimark-launcher');
  static const Key badgeKey = Key('banimark-launcher-badge');
  static const Key closeKey = Key('banimark-launcher-close');

  @override
  State<BanimarkLauncher> createState() => _BanimarkLauncherState();
}

class _BanimarkLauncherState extends State<BanimarkLauncher> {
  late final BanimarkController _c;
  late final bool _owns;
  BanimarkAppearance? _app;
  /// the bubble's spot as a fraction of the free area (0..1 each way), so a
  /// rotation or a different screen keeps it in the same corner
  Offset? _frac;
  bool _hidden = false;
  Timer? _back;
  int _lastUnread = 0;
  bool _chatOpen = false;

  String get _posKey => '${widget.storageKey}_pos';
  String get _untilKey => '${widget.storageKey}_hidden_until';

  Duration get _reappear => widget.reappearAfter ?? _app?.reappearAfter ?? const Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? BanimarkController(config: widget.config, visitor: widget.visitor);
    _lastUnread = _c.unread;
    // the chat is closed: listen slowly, only for the badge
    _c.active = false;
    if (widget.idlePollEvery != null) _c.idlePollEvery = widget.idlePollEvery!;
    _c.addListener(_onChange);
    if (_owns) _c.init();
    _restore();
    if (widget.followAdminAppearance) _loadAppearance();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pos = prefs.getString(_posKey);
      if (pos != null) {
        final p = pos.split(',');
        if (p.length == 2) {
          final x = double.tryParse(p[0]), y = double.tryParse(p[1]);
          if (x != null && y != null) _frac = Offset(x.clamp(0, 1), y.clamp(0, 1));
        }
      }
      final until = prefs.getInt(_untilKey);
      if (until != null) {
        final left = DateTime.fromMillisecondsSinceEpoch(until).difference(DateTime.now());
        if (left > Duration.zero) {
          _hidden = true;
          _back = Timer(left, _show);
        } else {
          await prefs.remove(_untilKey);
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _loadAppearance() async {
    final a = await BanimarkAppearance.fetch(widget.config);
    if (!mounted || a == null) return;
    _c.setIntervals(open: a.pollEvery, idle: widget.idlePollEvery ?? a.idlePollEvery);
    setState(() => _app = a);
  }

  void _onChange() {
    if (!mounted) return;
    // a reply from the team is the one thing that brings a dismissed bubble back
    if (_hidden && _c.unread > _lastUnread) _show();
    _lastUnread = _c.unread;
    setState(() {});
  }

  void _show() {
    _back?.cancel();
    _back = null;
    _hidden = false;
    SharedPreferences.getInstance().then((p) => p.remove(_untilKey)).catchError((_) => false);
    if (mounted) setState(() {});
  }

  void _dismiss() {
    final d = _reappear;
    setState(() => _hidden = true);
    if (d <= Duration.zero) return; // until the app is opened again - nothing stored
    _back?.cancel();
    _back = Timer(d, _show);
    final until = DateTime.now().add(d).millisecondsSinceEpoch;
    SharedPreferences.getInstance().then((p) => p.setInt(_untilKey, until)).catchError((_) => false);
  }

  Future<void> _open(BuildContext context) async {
    if (_chatOpen) return;
    _chatOpen = true;
    _c.markRead();
    _c.setActive(true);
    try {
      if (widget.onOpen != null) {
        widget.onOpen!(context, _c);
      } else {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => FractionallySizedBox(
            heightFactor: .92,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              child: BanimarkChat(
                config: widget.config,
                visitor: widget.visitor,
                theme: widget.theme,
                themeMode: widget.themeMode,
                controller: _c,
                followAdminAppearance: widget.followAdminAppearance,
                askGuestDetails: widget.askGuestDetails,
                emoji: widget.emoji,
                attachments: widget.attachments,
                onOpenLink: widget.onOpenLink,
                onClose: () => Navigator.of(ctx).pop(),
              ),
            ),
          ),
        );
      }
    } finally {
      _chatOpen = false;
      if (mounted) {
        _c.markRead();
        _c.setActive(false);
      }
    }
  }

  BanimarkTheme get _t {
    final base = widget.theme ??
        (switch (widget.themeMode) {
          ThemeMode.dark => BanimarkTheme.dark,
          ThemeMode.light => BanimarkTheme.light,
          _ => MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark ? BanimarkTheme.dark : BanimarkTheme.light,
        });
    final a = _app;
    if (a == null || widget.theme != null) return base;
    return a.applyTo(a.themeMode == ThemeMode.dark ? BanimarkTheme.dark : (a.themeMode == ThemeMode.light ? BanimarkTheme.light : base));
  }

  @override
  Widget build(BuildContext context) {
    final show = !_hidden && (_app?.enabled ?? true);
    return LayoutBuilder(builder: (context, box) {
      final pad = MediaQuery.paddingOf(context);
      final left0 = widget.margin.left + pad.left, top0 = widget.margin.top + pad.top;
      final freeW = (box.maxWidth - left0 - widget.margin.right - pad.right - widget.size).clamp(0.0, double.infinity);
      final freeH = (box.maxHeight - top0 - widget.margin.bottom - pad.bottom - widget.size).clamp(0.0, double.infinity);
      final frac = _frac ?? Offset((widget.initialAlignment.x + 1) / 2, (widget.initialAlignment.y + 1) / 2);
      final pos = Offset(left0 + frac.dx * freeW, top0 + frac.dy * freeH);

      void moveBy(Offset delta) {
        final nx = freeW == 0 ? 0.0 : ((pos.dx + delta.dx - left0) / freeW).clamp(0.0, 1.0);
        final ny = freeH == 0 ? 0.0 : ((pos.dy + delta.dy - top0) / freeH).clamp(0.0, 1.0);
        setState(() => _frac = Offset(nx, ny));
      }

      return Stack(children: [
        Positioned.fill(child: widget.child),
        if (show)
          Positioned(
            left: pos.dx,
            top: pos.dy,
            child: GestureDetector(
              key: BanimarkLauncher.bubbleKey,
              behavior: HitTestBehavior.opaque,
              onTap: () => _open(context),
              onPanUpdate: (d) => moveBy(d.delta),
              onPanEnd: (_) {
                final f = _frac;
                if (f == null) return;
                SharedPreferences.getInstance().then((p) => p.setString(_posKey, '${f.dx},${f.dy}')).catchError((_) => false);
              },
              child: _bubble(context),
            ),
          ),
      ]);
    });
  }

  Widget _bubble(BuildContext context) {
    final t = _t;
    final n = _c.unread;
    final body = widget.bubbleBuilder?.call(context, n) ??
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: t.primary,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: t.primary.withValues(alpha: .35), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Icon(Icons.chat_bubble_rounded, color: t.onPrimary, size: widget.size * .44),
        );
    return Semantics(
      button: true,
      label: n > 0 ? 'Open support chat, $n unread' : 'Open support chat',
      child: SizedBox(
        width: widget.size + 12,
        height: widget.size + 12,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(left: 6, top: 6, child: body),
          if (n > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                key: BanimarkLauncher.badgeKey,
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5484D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.background, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(n > 9 ? '9+' : '$n',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, height: 1)),
              ),
            ),
          if (widget.dismissible)
            Positioned(
              left: 0,
              top: 0,
              child: GestureDetector(
                key: BanimarkLauncher.closeKey,
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: Semantics(
                  button: true,
                  label: 'Hide chat bubble',
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(color: t.surface, shape: BoxShape.circle, border: Border.all(color: t.border)),
                    child: Icon(Icons.close_rounded, size: 13, color: t.muted),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _back?.cancel();
    _c.removeListener(_onChange);
    if (_owns) _c.dispose();
    super.dispose();
  }
}
