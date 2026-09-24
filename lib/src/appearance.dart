import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'theme.dart';

/// The look the desk owner chose in the admin panel (Widget page): accent
/// colour, title, greeting and light/dark. Fetched from the desk's public
/// appearance endpoint, so the app matches the website widget without a
/// release. Nothing secret travels here - the endpoint is the same allow-list
/// the website widget is built from.
class BanimarkAppearance {
  final Color? primary;
  final String? title;
  final String? greeting;
  final String? offlineNote;
  /// null = the admin chose "auto" (follow the device)
  final ThemeMode? themeMode;

  /// What a guest is asked for, and what they can tap to start - both set in
  /// the desk's admin panel, so the app matches the website without a release.
  final String? guestIntro;
  final List<BanimarkGuestField> guestFields;
  final List<String> starters;

  /// The line under the title (empty = the theme's own), and - out of hours -
  /// when a person is next around, which wins over it, as on the website.
  final String? statusLine;
  final String? awayNote;
  /// The owner's logo for the header, already absolute. null = the theme's avatar.
  final Uri? logo;
  /// 'rounded' (keep the theme's radii), 'soft' or 'square'.
  final String corner;
  final bool compact;
  /// false = the owner turned the reply chime off.
  final bool sound;
  /// false = a never-activated desk (no trial, no licence key): the chat is not
  /// live yet, so the SDK shows nothing to send. Older desks omit it (= true).
  final bool enabled;
  /// How often to look for a reply while the chat is open / while it is
  /// closed (the launcher's unread count), and how long a launcher the visitor
  /// dismissed stays away - all set on the desk's Widget page. null = the desk
  /// is older and does not say; the SDK keeps its own defaults.
  final Duration? pollEvery;
  final Duration? idlePollEvery;
  /// Duration.zero = stay away until the app is opened again.
  final Duration? reappearAfter;

  const BanimarkAppearance({this.primary, this.title, this.greeting, this.offlineNote, this.themeMode,
      this.guestIntro, this.guestFields = const [], this.starters = const [],
      this.statusLine, this.awayNote, this.logo, this.corner = 'rounded', this.compact = false, this.sound = true,
      this.enabled = true, this.pollEvery, this.idlePollEvery, this.reappearAfter});

  /// The last look read in this app run, per desk - so a chat opened after the
  /// launcher (or a second time) paints in the desk's colours from its first
  /// frame instead of flashing the default theme.
  static final Map<String, BanimarkAppearance> _memory = {};
  static String _key(BanimarkConfig config) => config.chat.toString();
  static String _storeKey(BanimarkConfig config) => 'banimark_appearance_${_key(config)}';

  /// What this app run already fetched for [config], if anything.
  static BanimarkAppearance? cached(BanimarkConfig config) => _memory[_key(config)];

  /// The look saved on the device by an earlier run (null on a first run).
  static Future<BanimarkAppearance?> stored(BanimarkConfig config) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_storeKey(config));
      return raw == null ? null : _parse(config, raw);
    } catch (_) {
      return null;
    }
  }

  static Future<BanimarkAppearance?> fetch(BanimarkConfig config, {http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      // …/banimark/chat  ->  …/banimark/widget/appearance   (…/chat -> …/widget/appearance standalone)
      final base = config.chat.toString().replaceFirst(RegExp(r'/chat$'), '');
      final res = await c
          .get(Uri.parse('$base/widget/appearance'), headers: {'Accept': 'application/json', ...config.headers})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final a = _parse(config, res.body);
      if (a == null) return null;
      _memory[_key(config)] = a;
      try {
        await (await SharedPreferences.getInstance()).setString(_storeKey(config), res.body);
      } catch (_) {}
      return a;
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  static BanimarkAppearance? _parse(BanimarkConfig config, String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map<String, dynamic>) return null;
      return BanimarkAppearance(
        primary: _hex(j['color']?.toString()),
        title: j['title']?.toString(),
        greeting: j['greeting']?.toString(),
        offlineNote: j['offline_note']?.toString(),
        themeMode: switch (j['theme']?.toString()) { 'dark' => ThemeMode.dark, 'light' => ThemeMode.light, _ => null },
        guestIntro: j['guest_intro']?.toString(),
        guestFields: ((j['guest_fields'] as List?) ?? const [])
            .map((f) => BanimarkGuestField.fromJson(Map<String, dynamic>.from(f as Map)))
            .toList(),
        starters: ((j['starters'] as List?) ?? const []).map((s) => s.toString()).toList(),
        statusLine: j['status_line']?.toString(),
        awayNote: j['away_note']?.toString(),
        // a standalone desk sends a path; resolve it against the chat endpoint
        logo: _logo(config, j['logo_url']?.toString()),
        corner: const ['soft', 'square'].contains(j['corner']) ? j['corner'] as String : 'rounded',
        compact: j['density'] == 'compact',
        sound: j['sound'] != false,
        enabled: j['enabled'] != false,
        pollEvery: _seconds(j['poll_seconds'], 3, 600),
        idlePollEvery: _seconds(j['poll_idle_seconds'], 10, 600),
        reappearAfter: j['launcher_reappear_minutes'] == null
            ? null
            : Duration(minutes: ((j['launcher_reappear_minutes'] as num?)?.toInt() ?? 10).clamp(0, 1440)),
      );
    } catch (_) {
      return null;
    }
  }

  static Uri? _logo(BanimarkConfig config, String? url) {
    if (url == null || url.isEmpty) return null;
    final u = config.chat.resolve(url);
    return (u.scheme == 'https' || u.scheme == 'http') ? u : null;
  }

  /// clamped exactly as the desk clamps it - a bad number must never become a request storm
  static Duration? _seconds(dynamic v, int min, int max) => v == null ? null : Duration(seconds: ((v as num?)?.toInt() ?? min).clamp(min, max));

  static Color? _hex(String? s) {
    if (s == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s)) return null;
    return Color(int.parse('FF${s.substring(1)}', radix: 16));
  }

  /// Lay the admin's choices over a theme; anything the admin left blank is kept.
  BanimarkTheme applyTo(BanimarkTheme t) {
    final on = primary == null ? t.onPrimary : (ThemeData.estimateBrightnessForColor(primary!) == Brightness.dark ? Colors.white : const Color(0xFF16202E));
    return t.copyWith(
      primary: primary ?? t.primary,
      onPrimary: on,
      userBubble: primary ?? t.userBubble,
      userBubbleText: on,
      title: (title ?? '').isEmpty ? t.title : title,
      greeting: (greeting ?? '').isEmpty ? t.greeting : greeting,
      subtitle: (awayNote ?? '').isNotEmpty ? awayNote : ((statusLine ?? '').isEmpty ? t.subtitle : statusLine),
      bubbleRadius: switch (corner) { 'soft' => 12.0, 'square' => 6.0, _ => t.bubbleRadius },
      inputRadius: switch (corner) { 'soft' => 14.0, 'square' => 6.0, _ => t.inputRadius },
      compact: compact || t.compact,
      avatar: logo == null ? t.avatar : _LogoAvatar(url: logo!, fallback: t.avatar, color: on),
    );
  }
}

/// The owner's logo in the header; a picture that will not load puts the
/// theme's own avatar (or the chat glyph) back, as the website widget does.
class _LogoAvatar extends StatelessWidget {
  final Uri url;
  final Widget? fallback;
  final Color color;
  const _LogoAvatar({required this.url, required this.fallback, required this.color});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url.toString(),
          width: 40, height: 40, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback ??
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: .18), shape: BoxShape.circle),
                child: Icon(Icons.chat_bubble_rounded, color: color, size: 20),
              ),
        ),
      );
}
