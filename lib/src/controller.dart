import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'client.dart';
import 'config.dart';
import 'models.dart';

/// All the state behind the chat screen - usable on its own if you want a
/// custom UI. Persists the session id so the visitor picks up where they left
/// off, polls for human replies after a handover, and never throws at the UI:
/// failures become a friendly message and a retry on the bubble.
class BanimarkController extends ChangeNotifier {
  final BanimarkClient client;
  final BanimarkConfig config;
  final String storageKey;

  BanimarkVisitor? visitor;
  String sessionId = '';
  BanimarkMode mode = BanimarkMode.ai;
  final List<BanimarkMessage> messages = [];
  bool thinking = false; // the AI is composing
  /// How long the typing dots stay up at minimum, so a fast answer does not snap in.
  Duration typingHold = const Duration(milliseconds: 900);
  bool agentTyping = false; // a human is typing on the other side
  /// files chosen but not yet sent - shown as chips above the composer
  final List<BanimarkAttachment> pending = [];
  final List<String> uploading = [];
  DateTime _typingSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool loading = true; // restoring history
  /// An older page of the thread exists (the server draws 15 at a time).
  bool hasMore = false;
  bool loadingEarlier = false;
  int _oldestId = 0;
  /// Staff replies that arrived while [markRead] has not been called - for a badge.
  /// Survives an app restart: the id of the last reply the visitor SAW is kept
  /// on the device and a restored thread counts what came after it.
  int unread = 0;
  /// Is the thread on screen? On: poll at [BanimarkConfig.pollEvery] (the
  /// heartbeat staff see). Off (a launcher with the chat closed): poll at
  /// [idlePollEvery], only to keep the unread count honest.
  bool active = true;
  /// How often a CLOSED chat looks for a reply. The desk's Widget page sets it
  /// (see [setIntervals]); 30 s until the desk says otherwise.
  Duration idlePollEvery = const Duration(seconds: 30);
  Duration? _openEvery;
  int _savedSeen = -1;
  /// Called for every reply from a human that arrives over the poll - play a
  /// sound, show a local notification, whatever the app does for new messages.
  void Function(BanimarkMessage message)? onStaffMessage;
  String? error;
  Timer? _poll;
  int _localId = -1;
  bool _disposed = false;

  BanimarkController({required this.config, this.visitor, BanimarkClient? client, this.storageKey = 'banimark_session'})
      : client = client ?? BanimarkClient(config);

  bool get needsVisitorDetails => (config.token ?? '').isEmpty && (visitor == null || visitor!.isEmpty);
  /// The interval the poll runs at right now.
  Duration get pollInterval => active ? (_openEvery ?? config.pollEvery) : idlePollEvery;
  String get _seenKey => '${storageKey}_seen';

  /// The thread came on screen (true) or went away (false): the poll changes pace.
  void setActive(bool on) {
    if (active == on) return;
    active = on;
    _schedule();
  }

  /// The desk owner's intervals (from [BanimarkAppearance]); null keeps the current one.
  void setIntervals({Duration? open, Duration? idle}) {
    if (open != null) _openEvery = open;
    if (idle != null) idlePollEvery = idle;
    _schedule();
  }
  int get _lastServerId => messages.where((m) => m.id > 0).fold(0, (a, m) => m.id > a ? m.id : a);

  /// Restore a previous conversation (if any) and start listening.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      sessionId = prefs.getString(storageKey) ?? '';
      // a signed-in user with nothing stored is matched to their open thread by the server
      if (sessionId.isNotEmpty || (config.token ?? '').isNotEmpty) {
        final h = await client.history(sessionId: sessionId);
        if (h.sessionId.isNotEmpty && h.sessionId != sessionId) {
          sessionId = h.sessionId;
          await prefs.setString(storageKey, sessionId);
        }
        if (h.messages.isNotEmpty) {
          messages
            ..clear()
            ..addAll(h.messages);
          mode = h.mode;
        }
        hasMore = h.hasMore;
        _oldestId = h.oldestId;
        // replies that landed while the app was closed. No mark yet (a visitor
        // from before this) = everything so far counts as seen, never as new.
        final seen = prefs.getInt(_seenKey);
        if (seen == null) {
          await _saveSeen(prefs);
        } else {
          unread = messages.where((m) => m.sender != BanimarkSender.user && m.id > seen).length;
        }
      }
    } catch (_) {
      // a failed restore is not an error the visitor needs to see
    }
    loading = false;
    _notify();
    _schedule();
  }

  void setVisitor(BanimarkVisitor v) {
    visitor = v;
    _notify();
  }

  /// Attach a file: it uploads immediately, so sending is instant and the
  /// message only ever carries ids the desk has already accepted.
  Future<void> attach({required String filename, required List<int> bytes}) async {
    if (sessionId.isEmpty) {
      error = 'Say hello first, then you can send a file.';
      _notify();
      return;
    }
    uploading.add(filename);
    _notify();
    try {
      pending.add(await client.upload(sessionId: sessionId, filename: filename, bytes: bytes));
    } catch (e) {
      error = e is BanimarkException ? e.message : 'That file could not be sent.';
    } finally {
      uploading.remove(filename);
      _notify();
    }
  }

  void removePending(BanimarkAttachment a) {
    pending.remove(a);
    _notify();
  }

  Future<void> send(String text) async {
    final t = text.trim();
    final files = List<BanimarkAttachment>.from(pending);
    if (t.isEmpty && files.isEmpty) return;
    final local = BanimarkMessage(id: _localId--, sender: BanimarkSender.user, text: t, at: DateTime.now(), pending: true, files: files);
    pending.clear();
    cleared = false;
    messages.add(local);
    error = null;
    // The dots appear after a short pause - as if the message was read first -
    // and stay for a moment even when the answer is instant. Instant dots and a
    // reply that snaps in read as a machine. While a human owns the chat the AI
    // dots never show; the real agent's typing comes over the poll.
    thinking = false;
    DateTime? dotsAt;
    Timer? dotsTimer;
    final dotsShown = Completer<void>();
    if (mode == BanimarkMode.ai) {
      dotsTimer = Timer(Duration(milliseconds: 600 + Random().nextInt(700)), () {
        dotsAt = DateTime.now();
        if (!_disposed) {
          thinking = true;
          _notify();
        }
        dotsShown.complete();
      });
    } else {
      dotsShown.complete();
    }
    _notify();
    try {
      final r = await client.send(message: t, sessionId: sessionId, visitor: visitor, attachments: files.map((f) => f.id).toList());
      // the answer may have beaten the dots: still show them, then hold a moment
      await dotsShown.future;
      if (dotsAt != null) {
        final shown = DateTime.now().difference(dotsAt!).inMilliseconds;
        if (shown < typingHold.inMilliseconds) await Future.delayed(typingHold - Duration(milliseconds: shown));
      }
      // ONE replace, carrying the verdict with it. Replacing twice lost the
      // second one - the first swap put a new object in the list, so indexOf()
      // no longer found `local` - and a message the desk refused (ok:false, a
      // 422) then looked delivered, with no failure mark and no way to resend.
      _replace(local, local.copyWith(pending: false, failed: !r.ok));
      if (r.sessionId.isNotEmpty && r.sessionId != sessionId) {
        sessionId = r.sessionId;
        try {
          (await SharedPreferences.getInstance()).setString(storageKey, sessionId);
        } catch (_) {}
      }
      mode = r.mode;
      if (!r.ok) {
        error = r.error ?? 'Something went wrong - please try again.';
      } else if (r.reply.isNotEmpty) {
        messages.add(BanimarkMessage(id: 0, sender: BanimarkSender.assistant, text: r.reply, at: DateTime.now()));
      }
    } catch (e) {
      dotsTimer?.cancel();
      if (!dotsShown.isCompleted) dotsShown.complete();
      error = e is BanimarkException ? e.message : 'No connection - check your internet and try again.';
      _replace(local, local.copyWith(pending: false, failed: true));
    }
    thinking = false;
    _notify();
    _schedule();
  }

  /// Fetch the page before the oldest message shown; returns how many arrived.
  Future<int> loadEarlier() async {
    if (!hasMore || loadingEarlier || _oldestId <= 0 || sessionId.isEmpty) return 0;
    loadingEarlier = true;
    _notify();
    try {
      final h = await client.history(sessionId: sessionId, beforeId: _oldestId);
      messages.insertAll(0, h.messages);
      hasMore = h.hasMore;
      _oldestId = h.oldestId > 0 ? h.oldestId : _oldestId;
      return h.messages.length;
    } catch (_) {
      return 0;
    } finally {
      loadingEarlier = false;
      _notify();
    }
  }

  /// The visitor has seen the thread - clear the unread count and remember
  /// how far they read, so a restart does not show the same replies as new.
  void markRead() {
    if (_savedSeen != _lastServerId) {
      SharedPreferences.getInstance().then(_saveSeen).catchError((_) {});
    }
    if (unread == 0) return;
    unread = 0;
    _notify();
  }

  Future<void> _saveSeen(SharedPreferences prefs) async {
    _savedSeen = _lastServerId;
    try {
      await prefs.setInt(_seenKey, _savedSeen);
    } catch (_) {}
  }

  /// Re-send a bubble that failed. (Its files were already stored, so they go again as they are.)
  Future<void> retry(BanimarkMessage failed) async {
    messages.remove(failed);
    pending.addAll(failed.files);
    await send(failed.text);
  }

  /// Call from the composer's onChanged: tells the desk the user is typing (throttled).
  void typing() {
    if (sessionId.isEmpty || mode != BanimarkMode.agent) return;
    if (DateTime.now().difference(_typingSent).inMilliseconds < 2500) return;
    _typingSent = DateTime.now();
    _tick(typing: true);
  }

  /// One poll, for tests.
  @visibleForTesting
  Future<void> tickForTest() => _tick();

  Future<void> _tick({bool typing = false}) async {
    if (sessionId.isEmpty || _disposed) return;
    try {
      final r = await client.poll(sessionId: sessionId, afterId: _lastServerId, typing: typing);
      var changed = r.mode != mode || r.agentTyping != agentTyping;
      mode = r.mode;
      agentTyping = r.agentTyping && r.messages.isEmpty;
      for (final m in r.messages) {
        if (!messages.any((x) => x.id == m.id)) {
          messages.add(m);
          changed = true;
          if (m.sender != BanimarkSender.user) {
            unread++;
            try { onStaffMessage?.call(m); } catch (_) { /* the app's handler must not break polling */ }
          }
        }
      }
      if (changed) _notify();
    } catch (_) {
      // transient - the next tick tries again
    }
  }

  void _schedule() {
    _poll?.cancel();
    if (sessionId.isEmpty) return;
    _poll = Timer.periodic(pollInterval, (_) => _tick());
  }

  /// The conversation was just deleted - the screen says so until the next message.
  bool cleared = false;

  /// The visitor deletes their conversation: the desk hides it from them
  /// (soft - the team keeps it until it is erased), and this device starts
  /// over. False (with [error] set) when the desk could not be reached.
  Future<bool> deleteConversation() async {
    if (sessionId.isNotEmpty) {
      try {
        if (!await client.deleteConversation(sessionId: sessionId)) {
          error = 'The conversation could not be deleted just now. Please try again.';
          _notify();
          return false;
        }
      } catch (e) {
        error = e is BanimarkException ? e.message : 'The conversation could not be deleted just now. Please try again.';
        _notify();
        return false;
      }
    }
    pending.clear();
    hasMore = false;
    _oldestId = 0;
    agentTyping = false;
    error = null;
    cleared = true;
    await reset();
    return true;
  }

  /// Forget the conversation on this device (e.g. on logout).
  Future<void> reset() async {
    sessionId = '';
    messages.clear();
    mode = BanimarkMode.ai;
    _poll?.cancel();
    unread = 0;
    _savedSeen = -1;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
      await prefs.remove(_seenKey);
    } catch (_) {}
    _notify();
  }

  void _replace(BanimarkMessage a, BanimarkMessage b) {
    final i = messages.indexOf(a);
    if (i >= 0) messages[i] = b;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    client.close();
    super.dispose();
  }
}
