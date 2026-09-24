import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'controller.dart';
import 'models.dart';
import 'theme.dart';
import 'appearance.dart';
import 'emoji.dart';
import 'markdown.dart';
import 'tour.dart';

/// Signature for replacing a bubble entirely.
typedef BanimarkBubbleBuilder = Widget Function(BuildContext context, BanimarkMessage message, BanimarkTheme theme);

/// The complete chat screen: header with presence, animated bubbles, typing
/// indicator, human-handover banner, optional guest form, composer. Drop it in
/// a route, a bottom sheet or a tab - it sizes to whatever you give it.
class BanimarkChat extends StatefulWidget {
  final BanimarkConfig config;
  final BanimarkVisitor? visitor;
  final BanimarkTheme? theme;

  /// Bring your own controller to keep the conversation alive across screens.
  final BanimarkController? controller;

  /// Hide the built-in header when you embed inside your own AppBar/sheet.
  final bool showHeader;
  final VoidCallback? onClose;
  final BanimarkBubbleBuilder? bubbleBuilder;

  /// Ask guests for name + email before the first message (ignored when a
  /// signed token identifies the visitor).
  final bool askGuestDetails;

  /// Show the emoji keyboard button.
  final bool emoji;

  /// Show the paperclip. The desk can also switch files off for everyone.
  final bool attachments;

  /// Called when a link in a message is tapped. Defaults to opening the link in
  /// the device browser (url_launcher, external application); pass your own to
  /// handle it differently (in-app webview, analytics, etc.).
  final void Function(Uri uri)? onOpenLink;

  /// Light, dark, or follow the device. Ignored when [theme] is given.
  final ThemeMode themeMode;

  /// Fetch the appearance the desk owner set in the admin panel (accent colour,
  /// title, greeting, light/dark) and apply it over [theme]/[themeMode].
  final bool followAdminAppearance;

  /// First time the chat opens on a device, point out the emoji, paperclip,
  /// send and delete buttons, one at a time. Each spot is shown once; the bin
  /// waits until there is a conversation to delete. Texts are on [BanimarkTheme]
  /// (`tourEmoji`, `tourAttach`, ...).
  final bool showTour;

  /// Device storage key for which tour spots were seen. Reset it with
  /// `BanimarkChat.resetTour()` to show the tour again.
  final String tourStorageKey;

  static const String defaultTourKey = 'banimark_tour_seen';

  /// Show the tour again next time the chat opens.
  static Future<void> resetTour([String storageKey = defaultTourKey]) => BanimarkTourMemory(storageKey).reset();

  static const Key emojiKey = Key('banimark-emoji');
  static const Key attachKey = Key('banimark-attach');

  const BanimarkChat({
    super.key,
    required this.config,
    this.visitor,
    this.theme,
    this.controller,
    this.showHeader = true,
    this.onClose,
    this.bubbleBuilder,
    this.askGuestDetails = true,
    this.themeMode = ThemeMode.system,
    this.followAdminAppearance = false,
    this.emoji = true,
    this.attachments = true,
    this.onOpenLink,
    this.showTour = false,
    this.tourStorageKey = defaultTourKey,
  });

  @override
  State<BanimarkChat> createState() => _BanimarkChatState();
}

class _BanimarkChatState extends State<BanimarkChat> {
  late final BanimarkController _c;
  late final bool _ownsController;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  BanimarkMode? _lastMode;
  bool _emojiOpen = false;

  // what the tour points at
  final _emojiSpot = GlobalKey(debugLabel: 'banimark-tour-emoji');
  final _attachSpot = GlobalKey(debugLabel: 'banimark-tour-attach');
  final _sendSpot = GlobalKey(debugLabel: 'banimark-tour-send');
  final _deleteSpot = GlobalKey(debugLabel: 'banimark-tour-delete');
  OverlayEntry? _tour;
  Set<String>? _tourSeen;
  bool _tourChecking = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _c = widget.controller ?? BanimarkController(config: widget.config, visitor: widget.visitor);
    _heard = _c.unread;
    _c.addListener(_onChange);
    if (_ownsController) _c.init();
    if (widget.followAdminAppearance) _appearance = BanimarkAppearance.cached(widget.config);
    _lookReady = !widget.followAdminAppearance || _appearance != null;
    _loadAppearance();
  }

  int _heard = 0;
  void _onChange() {
    if (!mounted) return;
    // a reply from the team: the same soft cue the website plays, unless the owner turned it off
    if (_c.unread > _heard && (_appearance?.sound ?? true)) SystemSound.play(SystemSoundType.alert);
    _heard = _c.unread;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  Future<void> _send() async {
    final t = _input.text;
    if (t.trim().isEmpty && _c.pending.isEmpty) return;
    _input.clear();
    setState(() => _emojiOpen = false);
    await _c.send(t);
    _focus.requestFocus();
  }

  Future<void> _pickFile() async {
    setState(() => _emojiOpen = false);
    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    if (f.bytes == null) return;
    await _c.attach(filename: f.name, bytes: f.bytes!);
  }

  BanimarkAppearance? _appearance;
  /// false until the desk's look is known (cache, device or network), so the
  /// chat never paints in the default colours and then switches
  bool _lookReady = true;

  BanimarkTheme get _t {
    final a = _appearance;
    final mode = a?.themeMode ?? widget.themeMode;
    final dark = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => Theme.of(context).brightness == Brightness.dark,
    };
    var base = widget.theme ?? (dark ? BanimarkTheme.dark : BanimarkTheme.light);
    if (widget.theme != null && a?.themeMode != null && a!.themeMode != ThemeMode.system) {
      // the admin forced a mode: keep the app's colours, swap the palette side
      base = dark ? BanimarkTheme.dark.copyWith(primary: widget.theme!.primary, onPrimary: widget.theme!.onPrimary, userBubble: widget.theme!.primary, userBubbleText: widget.theme!.onPrimary)
                  : BanimarkTheme.light.copyWith(primary: widget.theme!.primary, onPrimary: widget.theme!.onPrimary, userBubble: widget.theme!.primary, userBubbleText: widget.theme!.onPrimary);
    }
    return a == null ? base : a.applyTo(base);
  }

  /// The built-in link handler: open in the device browser. Overridden by a
  /// caller-supplied onOpenLink. Never throws - a link that will not open is
  /// silently ignored rather than crashing the chat.
  Future<void> _openLink(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      /* nothing sensible to do on a device with no browser/handler */
    }
  }

  Future<void> _loadAppearance() async {
    if (!widget.followAdminAppearance) return;
    if (_appearance == null) {
      final saved = await BanimarkAppearance.stored(widget.config);
      if (mounted && saved != null) setState(() { _appearance = saved; _lookReady = true; });
    }
    final a = await BanimarkAppearance.fetch(widget.config);
    if (!mounted) return;
    setState(() {
      if (a != null) _appearance = a;
      _lookReady = true;
    });
  }

  /// After a frame: any spot on screen that this device has not seen yet? Only
  /// when the chat is at rest - not loading, no keyboard, no reply on its way.
  Future<void> _maybeTour() async {
    if (!widget.showTour || _tour != null || _tourChecking || !mounted) return;
    _tourChecking = true;
    try {
      _tourSeen ??= await BanimarkTourMemory(widget.tourStorageKey).seen();
      if (!mounted || _tour != null) return;
      if (!_lookReady || _c.loading || _c.thinking || MediaQuery.viewInsetsOf(context).bottom > 0) return;
      final t = _t;
      final steps = [
        BanimarkTourStep(id: 'emoji', target: _emojiSpot, text: t.tourEmoji),
        BanimarkTourStep(id: 'attach', target: _attachSpot, text: t.tourAttach),
        BanimarkTourStep(id: 'send', target: _sendSpot, text: t.tourSend),
        BanimarkTourStep(id: 'delete', target: _deleteSpot, text: t.tourDelete),
      ].where((s) => !_tourSeen!.contains(s.id) && s.target.currentContext != null).toList();
      if (steps.isEmpty) return;
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) return;
      _focus.unfocus();
      _tour = OverlayEntry(
        builder: (_) => BanimarkTourOverlay(
          steps: steps,
          theme: t,
          onFinish: (skipped) {
            _tour?.remove();
            _tour = null;
            // skipping means "no tour", including the spots still to come
            final ids = skipped ? const ['emoji', 'attach', 'send', 'delete'] : steps.map((s) => s.id);
            _tourSeen!.addAll(ids);
            BanimarkTourMemory(widget.tourStorageKey).markSeen(ids);
          },
        ),
      );
      overlay.insert(_tour!);
    } finally {
      _tourChecking = false;
    }
  }

  @override
  void dispose() {
    _tour?.remove();
    _tour = null;
    _c.removeListener(_onChange);
    if (_ownsController) _c.dispose();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // above the keyboard wherever the chat sits (a sheet, a dialog, a tab). A
    // Scaffold that already resizes removes the inset first, so it never doubles.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final t = _t;
    if (widget.showTour && _tour == null) WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTour());
    if (!_lookReady) {
      return Material(
        color: t.background,
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: t.muted))),
      );
    }
    final handover = _lastMode != null && _lastMode != BanimarkMode.agent && _c.mode == BanimarkMode.agent;
    _lastMode = _c.mode;
    if (handover) WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());

    // A never-activated desk (no trial, no licence key) serves no chat yet:
    // show the header and a quiet notice, no composer. Older desks omit the
    // flag (enabled defaults to true), so nothing changes for them.
    if (_appearance != null && !_appearance!.enabled) {
      return Material(
        color: t.background,
        child: Column(children: [
          if (widget.showHeader) _Header(theme: t, mode: _c.mode, onClose: widget.onClose, onDelete: _c.sessionId.isEmpty ? null : () => _confirmDelete(t)),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text('Chat is not available right now.',
                    textAlign: TextAlign.center, style: TextStyle(color: t.muted, fontSize: 15)),
              ),
            ),
          ),
        ]),
      );
    }

    return Material(
      color: t.background,
      child: Column(
        children: [
          if (widget.showHeader) _Header(theme: t, mode: _c.mode, onClose: widget.onClose, deleteSpot: _deleteSpot, onDelete: _c.sessionId.isEmpty ? null : () => _confirmDelete(t)),
          Expanded(
            child: _c.loading
                ? Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: t.primary)))
                : (widget.askGuestDetails && _c.needsVisitorDetails && _c.messages.isEmpty)
                    ? _GuestForm(theme: t, onDone: _c.setVisitor, fields: _appearance?.guestFields ?? const [], intro: _appearance?.guestIntro)
                    : _thread(t),
          ),
          if (_c.error != null) _ErrorBar(theme: t, text: _c.error!),
          if (_c.pending.isNotEmpty || _c.uploading.isNotEmpty) _PendingStrip(theme: t, controller: _c),
          if (_c.mode != BanimarkMode.closed)
            _Composer(
              theme: t, controller: _input, focus: _focus, onSend: _send, busy: _c.thinking, onTyping: _c.typing,
              onEmoji: widget.emoji ? () => setState(() => _emojiOpen = !_emojiOpen) : null,
              onAttach: widget.attachments ? _pickFile : null,
              emojiOpen: _emojiOpen,
              emojiSpot: _emojiSpot, attachSpot: _attachSpot, sendSpot: _sendSpot,
            ),
          if (_emojiOpen && widget.emoji)
            BanimarkEmojiPicker(theme: t, onPick: (e) {
              final sel = _input.selection;
              final at = sel.start < 0 ? _input.text.length : sel.start;
              final end = sel.end < 0 ? at : sel.end;
              _input.text = _input.text.replaceRange(at, end, e);
              _input.selection = TextSelection.collapsed(offset: at + e.length);
              setState(() {});
            }),
        ],
      ),
    );
  }

  bool _earlierArmed = true;
  void _onScroll() {
    // reaching the top pulls the page before it; the offset is restored after
    // the new bubbles are laid out so the thread does not jump
    if (!_c.hasMore || _c.loadingEarlier || !_scroll.hasClients) return;
    if (_scroll.position.pixels <= 24 && _earlierArmed) {
      _earlierArmed = false;
      _loadEarlier();
    } else if (_scroll.position.pixels > 80) {
      _earlierArmed = true;
    }
  }

  Future<void> _loadEarlier() async {
    final before = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final got = await _c.loadEarlier();
    if (got == 0 || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final delta = _scroll.position.maxScrollExtent - before;
      if (delta > 0) _scroll.jumpTo(_scroll.position.pixels + delta);
    });
  }

  Future<void> _confirmDelete(BanimarkTheme t) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteTitle),
        content: Text(t.deleteBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancelLabel)),
          TextButton(
            key: const Key('banimark-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: t.danger),
            child: Text(t.deleteButton),
          ),
        ],
      ),
    );
    if (yes == true) await _c.deleteConversation();
  }

  Widget _thread(BanimarkTheme t) {
    // the thread is on screen: whatever arrived has been seen
    WidgetsBinding.instance.addPostFrameCallback((_) => _c.markRead());
    final items = <Widget>[];
    if (_c.hasMore || _c.loadingEarlier) {
      items.add(Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _c.loadingEarlier
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.8, color: t.muted))
              : OutlinedButton(
                  onPressed: _loadEarlier,
                  style: OutlinedButton.styleFrom(foregroundColor: t.muted, side: BorderSide(color: t.border), shape: const StadiumBorder(), visualDensity: VisualDensity.compact),
                  child: Text(t.loadEarlierLabel, style: const TextStyle(fontSize: 12)),
                ),
        ),
      ));
    }
    if (_c.cleared && _c.messages.isEmpty) {
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(child: Text(t.deletedNotice, key: const Key('banimark-deleted'), style: TextStyle(color: t.muted, fontSize: 12.5))),
      ));
    }
    if (_c.messages.isEmpty && t.greeting.isNotEmpty) {
      items.add(_Bubble(theme: t, config: widget.config, message: BanimarkMessage(id: 0, sender: BanimarkSender.assistant, text: t.greeting, at: DateTime.now())));
    }
    BanimarkSender? prev;
    for (final m in _c.messages) {
      final first = prev != m.sender;
      prev = m.sender;
      items.add(widget.bubbleBuilder?.call(context, m, t) ??
          _Bubble(theme: t, config: widget.config, message: m, showAvatar: first, onRetry: m.failed ? () => _c.retry(m) : null, onOpenLink: widget.onOpenLink ?? _openLink));
    }
    // tappable openers, while the visitor has not said anything yet
    final starters = _appearance?.starters ?? const <String>[];
    if (starters.isNotEmpty && !_c.messages.any((m) => m.sender == BanimarkSender.user)) {
      items.add(Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in starters)
            ActionChip(
              label: Text(s, style: TextStyle(fontSize: 12.5, color: t.text)),
              backgroundColor: t.surface,
              side: BorderSide(color: t.border),
              shape: const StadiumBorder(),
              onPressed: () => _c.send(s),
            ),
        ]),
      ));
    }
    if (_c.mode == BanimarkMode.agent) items.add(_Banner(theme: t, text: t.handoverLabel));
    if (_c.thinking) items.add(_Typing(theme: t));
    if (_c.agentTyping) items.add(_Typing(theme: t, label: t.agentTypingLabel));
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _onScroll();
        return false;
      },
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
        children: items,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final BanimarkTheme theme;
  final BanimarkMode mode;
  final VoidCallback? onClose;
  /// null = nothing to delete yet (no conversation) - the bin is not shown
  final VoidCallback? onDelete;
  final GlobalKey? deleteSpot;
  const _Header({required this.theme, required this.mode, this.onClose, this.onDelete, this.deleteSpot});

  @override
  Widget build(BuildContext context) {
    final sub = switch (mode) { BanimarkMode.agent => theme.agentSubtitle, BanimarkMode.closed => theme.closedSubtitle, _ => theme.subtitle };
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + (theme.compact ? 8 : 12), 8, theme.compact ? 10 : 14),
      decoration: BoxDecoration(
        color: theme.primary,
        boxShadow: [BoxShadow(color: theme.primary.withValues(alpha: .28), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Row(children: [
        Stack(clipBehavior: Clip.none, children: [
          theme.avatar ??
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: theme.onPrimary.withValues(alpha: .18), shape: BoxShape.circle),
                child: Icon(Icons.chat_bubble_rounded, color: theme.onPrimary, size: 20),
              ),
          Positioned(
            right: -1, bottom: -1,
            child: Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                color: mode == BanimarkMode.closed ? theme.muted : const Color(0xFF1BAF7A),
                shape: BoxShape.circle, border: Border.all(color: theme.primary, width: 2),
              ),
            ),
          ),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(theme.title, style: theme.titleStyle ?? TextStyle(color: theme.onPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(sub, key: ValueKey(sub), style: TextStyle(color: theme.onPrimary.withValues(alpha: .8), fontSize: 12)),
            ),
          ]),
        ),
        if (onDelete != null)
          KeyedSubtree(key: deleteSpot, child: IconButton(key: const Key('banimark-delete'), tooltip: theme.deleteTitle.replaceAll('?', ''), onPressed: onDelete, icon: Icon(Icons.delete_outline_rounded, color: theme.onPrimary))),
        if (onClose != null) IconButton(onPressed: onClose, icon: Icon(Icons.close_rounded, color: theme.onPrimary)),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final BanimarkTheme theme;
  final BanimarkMessage message;
  final bool showAvatar;
  final VoidCallback? onRetry;
  final BanimarkConfig config;
  final void Function(Uri uri)? onOpenLink;
  const _Bubble({required this.theme, required this.message, required this.config, this.showAvatar = true, this.onRetry, this.onOpenLink});

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final agent = message.sender == BanimarkSender.agent;
    final bg = mine ? theme.userBubble : (agent ? theme.agentBubble : theme.botBubble);
    final fg = mine ? theme.userBubbleText : (agent ? theme.agentBubbleText : theme.botBubbleText);
    final r = theme.bubbleRadius;
    final avatar = agent ? theme.agentAvatar : theme.botAvatar;
    final showSide = !mine && (avatar != null || true);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child)),
      child: Padding(
        padding: EdgeInsets.only(bottom: theme.compact ? 3 : 6),
        child: Row(
          mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (showSide)
              SizedBox(
                width: 30,
                child: showAvatar
                    ? (avatar ??
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: agent ? const Color(0xFFEB6834) : theme.primary,
                          child: Icon(agent ? Icons.person_rounded : Icons.auto_awesome_rounded, size: 14, color: Colors.white),
                        ))
                    : null,
              ),
            if (showSide) const SizedBox(width: 6),
            Flexible(
              child: GestureDetector(
                onTap: onRetry,
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .74),
                  padding: theme.compact ? const EdgeInsets.symmetric(horizontal: 11, vertical: 7) : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: bg,
                    border: mine ? null : Border.all(color: theme.border),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(r), topRight: Radius.circular(r),
                      bottomLeft: Radius.circular(mine ? r : 6), bottomRight: Radius.circular(mine ? 6 : r),
                    ),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    if (message.text.isNotEmpty)
                      BanimarkMarkdown(
                        text: message.text,
                        style: (theme.messageStyle ?? TextStyle(fontSize: theme.compact ? 14 : 15, height: 1.35)).copyWith(color: fg),
                        linkColor: fg,
                        onOpenLink: onOpenLink,
                      ),
                    for (final f in message.files) _Attachment(theme: theme, file: f, config: config, fg: fg),
                    if (message.pending || message.failed || agent)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          message.failed ? theme.retryLabel : (message.pending ? '…' : 'Human agent'),
                          style: TextStyle(fontSize: 10.5, color: message.failed ? theme.danger : fg.withValues(alpha: .65)),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Typing extends StatefulWidget {
  final BanimarkTheme theme;
  final String? label;
  const _Typing({required this.theme, this.label});
  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  @override
  void dispose() { _a.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return Padding(
      padding: const EdgeInsets.only(left: 36, bottom: 6),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: t.botBubble, border: Border.all(color: t.border), borderRadius: BorderRadius.circular(t.bubbleRadius)),
          child: AnimatedBuilder(
            animation: _a,
            builder: (_, __) => Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final p = ((_a.value + i * .2) % 1.0);
                final y = p < .5 ? -4 * (p / .5) : -4 * (1 - (p - .5) / .5);
                return Transform.translate(
                  offset: Offset(0, y),
                  child: Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(color: t.muted, shape: BoxShape.circle)),
                );
              }),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(widget.label ?? t.thinkingLabel, style: TextStyle(fontSize: 12, color: t.muted)),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  final BanimarkTheme theme;
  final String text;
  const _Banner({required this.theme, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Expanded(child: Divider(color: theme.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.support_agent_rounded, size: 14, color: Color(0xFFEB6834)),
              const SizedBox(width: 6),
              Text(text, style: TextStyle(fontSize: 12, color: theme.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
          Expanded(child: Divider(color: theme.border)),
        ]),
      );
}

class _ErrorBar extends StatelessWidget {
  final BanimarkTheme theme;
  final String text;
  const _ErrorBar({required this.theme, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: theme.danger.withValues(alpha: .1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(text, style: TextStyle(color: theme.danger, fontSize: 12.5)),
      );
}

/// The message bar: emoji on the left and paperclip on the right INSIDE the
/// box, so the text gets the whole width; the send button beside it.
class _Composer extends StatelessWidget {
  final BanimarkTheme theme;
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onSend;
  final bool busy;
  final VoidCallback? onTyping;
  final VoidCallback? onEmoji;
  final VoidCallback? onAttach;
  final bool emojiOpen;
  final GlobalKey? emojiSpot, attachSpot, sendSpot;
  const _Composer({required this.theme, required this.controller, required this.focus, required this.onSend, required this.busy,
      this.onTyping, this.onEmoji, this.onAttach, this.emojiOpen = false, this.emojiSpot, this.attachSpot, this.sendSpot});

  Widget _inBox(Key key, GlobalKey? spot, String tip, IconData icon, VoidCallback onTap) => KeyedSubtree(
        key: spot,
        child: IconButton(
          key: key,
          onPressed: onTap,
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 42, height: 46),
          icon: Icon(icon, color: theme.muted, size: 23),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: theme.surface, border: Border(top: BorderSide(color: theme.border))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: theme.background, borderRadius: BorderRadius.circular(theme.inputRadius), border: Border.all(color: theme.border)),
            // icons sit on the last line as the text grows
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (onEmoji != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: _inBox(BanimarkChat.emojiKey, emojiSpot, 'Emoji',
                      emojiOpen ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined, onEmoji!),
                ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  minLines: 1,
                  maxLines: 6,
                  // Enter adds a line; the button sends
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => onTyping?.call(),
                  style: TextStyle(color: theme.text, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: theme.placeholder,
                    hintStyle: TextStyle(color: theme.muted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.fromLTRB(onEmoji == null ? 16 : 2, 13, onAttach == null ? 16 : 2, 13),
                  ),
                ),
              ),
              if (onAttach != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _inBox(BanimarkChat.attachKey, attachSpot, 'Attach a file', Icons.attach_file_rounded, onAttach!),
                ),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        // while a reply is on its way the typing dots say so; the button just rests
        AnimatedOpacity(
          key: sendSpot,
          opacity: busy ? .5 : 1,
          duration: const Duration(milliseconds: 150),
          child: Material(
            key: const Key('banimark-send'),
            color: theme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: busy ? null : onSend,
              child: SizedBox(width: 48, height: 48, child: Icon(theme.sendIcon, color: theme.onPrimary)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _GuestForm extends StatefulWidget {
  final BanimarkTheme theme;
  final ValueChanged<BanimarkVisitor> onDone;
  /// What the desk asks for. Empty = the old name + email pair.
  final List<BanimarkGuestField> fields;
  final String? intro;
  const _GuestForm({required this.theme, required this.onDone, this.fields = const [], this.intro});
  @override
  State<_GuestForm> createState() => _GuestFormState();
}

class _GuestFormState extends State<_GuestForm> {
  late final List<BanimarkGuestField> _fields = widget.fields.isNotEmpty
      ? widget.fields
      : const [
          BanimarkGuestField(key: 'name', label: 'Your name', required: true),
          BanimarkGuestField(key: 'email', label: 'you@example.com', type: 'email', required: true),
        ];
  late final Map<String, TextEditingController> _controllers = {
    for (final f in _fields) f.key: TextEditingController(),
  };
  String? _err;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextInputType _keyboard(String type) => switch (type) {
        'email' => TextInputType.emailAddress,
        'tel' => TextInputType.phone,
        _ => TextInputType.text,
      };

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: t.muted),
          filled: true, fillColor: t.surface,
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.primary, width: 1.5)),
        );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 8),
        Text(t.guestTitle, style: TextStyle(color: t.text, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(widget.intro?.isNotEmpty == true ? widget.intro! : t.guestHint, style: TextStyle(color: t.muted)),
        const SizedBox(height: 18),
        for (final f in _fields) ...[
          TextField(
            controller: _controllers[f.key],
            decoration: deco(f.required ? '${f.label} *' : f.label),
            style: TextStyle(color: t.text),
            keyboardType: _keyboard(f.type),
            textInputAction: f == _fields.last ? TextInputAction.done : TextInputAction.next,
          ),
          const SizedBox(height: 12),
        ],
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: t.danger, fontSize: 12.5))),
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: t.primary, foregroundColor: t.onPrimary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: () {
            final values = {for (final e in _controllers.entries) e.key: e.value.text.trim()};
            final missing = _fields.where((f) => f.required && (values[f.key] ?? '').isEmpty).toList();
            if (missing.isNotEmpty) {
              setState(() => _err = 'Please fill in ${missing.map((f) => f.label).join(' and ')}.');
              return;
            }
            final email = values['email'] ?? '';
            if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
              setState(() => _err = 'That email address does not look right.');
              return;
            }
            widget.onDone(BanimarkVisitor(name: values['name'], email: email, phone: values['phone']));
          },
          child: Text(t.guestButton),
        ),
      ],
    );
  }
}

/// One file inside a bubble: images preview, everything else is a tappable row.
class _Attachment extends StatelessWidget {
  final BanimarkTheme theme;
  final BanimarkAttachment file;
  final BanimarkConfig config;
  final Color fg;
  const _Attachment({required this.theme, required this.file, required this.config, required this.fg});

  @override
  Widget build(BuildContext context) {
    final url = file.url(config).toString();
    if (file.isImage) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url, width: 210, fit: BoxFit.cover,
            headers: config.headers,
            errorBuilder: (_, __, ___) => _row(context, url),
            loadingBuilder: (c, child, p) => p == null
                ? child
                : SizedBox(width: 210, height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: theme.primary))),
          ),
        ),
      );
    }
    return _row(context, url);
  }

  Widget _row(BuildContext context, String url) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: fg.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: fg.withValues(alpha: .18)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.insert_drive_file_outlined, size: 17, color: fg),
            const SizedBox(width: 7),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
                if (file.readableSize.isNotEmpty)
                  Text(file.readableSize, style: TextStyle(color: fg.withValues(alpha: .7), fontSize: 11)),
              ]),
            ),
          ]),
        ),
      );
}

/// Files chosen but not yet sent.
class _PendingStrip extends StatelessWidget {
  final BanimarkTheme theme;
  final BanimarkController controller;
  const _PendingStrip({required this.theme, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: theme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final name in controller.uploading)
          _chip(name, trailing: SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.6, color: theme.muted))),
        for (final f in controller.pending)
          _chip(f.name,
              subtitle: f.readableSize,
              trailing: InkWell(onTap: () => controller.removePending(f), child: Icon(Icons.close_rounded, size: 14, color: theme.muted))),
      ]),
    );
  }

  Widget _chip(String name, {String? subtitle, Widget? trailing}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(color: theme.background, border: Border.all(color: theme.border), borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: theme.text)),
          ),
          if (subtitle != null) ...[const SizedBox(width: 5), Text(subtitle, style: TextStyle(fontSize: 10.5, color: theme.muted))],
          if (trailing != null) ...[const SizedBox(width: 6), trailing],
        ]),
      );
}
