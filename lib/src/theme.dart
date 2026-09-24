import 'package:flutter/material.dart';

/// Every colour, radius and string the chat screen uses. Start from
/// [BanimarkTheme.light] / [BanimarkTheme.dark] / [BanimarkTheme.fromScheme]
/// and override what you need with [copyWith].
class BanimarkTheme {
  final Color primary;
  final Color onPrimary;
  final Color background;
  final Color surface;
  final Color border;
  final Color text;
  final Color muted;
  final Color userBubble;
  final Color userBubbleText;
  final Color botBubble;
  final Color botBubbleText;
  final Color agentBubble;
  final Color agentBubbleText;
  final Color danger;
  final double bubbleRadius;
  final double inputRadius;
  final TextStyle? messageStyle;
  final TextStyle? titleStyle;
  /// Tighter bubbles and header, so more of the conversation fits.
  final bool compact;

  final String title;
  final String subtitle;
  final String agentSubtitle;
  final String closedSubtitle;
  final String placeholder;
  final String thinkingLabel;
  final String agentTypingLabel;
  final String handoverLabel;
  final String guestTitle;
  final String guestHint;
  final String guestNameLabel;
  final String guestEmailLabel;
  final String guestButton;
  final String retryLabel;
  final String loadEarlierLabel;
  final String greeting;

  /// Header avatar (your logo). Defaults to a chat glyph on [primary].
  final Widget? avatar;
  /// Small avatar shown beside AI / agent bubbles; null hides it.
  final Widget? botAvatar;
  final Widget? agentAvatar;
  final IconData sendIcon;
  /// Deleting the conversation (the bin in the header).
  final String deleteTitle;
  final String deleteBody;
  final String deleteButton;
  final String cancelLabel;
  final String deletedNotice;

  const BanimarkTheme({
    required this.primary,
    required this.onPrimary,
    required this.background,
    required this.surface,
    required this.border,
    required this.text,
    required this.muted,
    required this.userBubble,
    required this.userBubbleText,
    required this.botBubble,
    required this.botBubbleText,
    required this.agentBubble,
    required this.agentBubbleText,
    this.danger = const Color(0xFFD9483B),
    this.bubbleRadius = 18,
    this.inputRadius = 24,
    this.messageStyle,
    this.titleStyle,
    this.compact = false,
    this.title = 'Support',
    this.subtitle = 'Typically replies in seconds',
    this.agentSubtitle = 'You are chatting with a human',
    this.closedSubtitle = 'This conversation is closed',
    this.placeholder = 'Write a message…',
    this.thinkingLabel = 'Thinking…',
    this.agentTypingLabel = 'Typing…',
    this.handoverLabel = 'A member of our team has joined the chat',
    this.guestTitle = 'Before we start',
    this.guestHint = 'So we can follow up if you step away.',
    this.guestNameLabel = 'Your name',
    this.guestEmailLabel = 'Email',
    this.guestButton = 'Start chatting',
    this.retryLabel = 'Tap to retry',
    this.loadEarlierLabel = 'Load earlier messages',
    this.greeting = 'Hi! Ask me anything - I can look things up for you and bring in a human if needed.',
    this.avatar,
    this.botAvatar,
    this.agentAvatar,
    this.sendIcon = Icons.arrow_upward_rounded,
    this.deleteTitle = 'Delete this conversation?',
    this.deleteBody = 'It will be cleared from this chat and you will not be able to see it again.',
    this.deleteButton = 'Delete',
    this.cancelLabel = 'Cancel',
    this.deletedNotice = 'Your conversation was deleted.',
  });

  static const BanimarkTheme light = BanimarkTheme(
    primary: Color(0xFF2A78D6),
    onPrimary: Colors.white,
    background: Color(0xFFF5F7FB),
    surface: Colors.white,
    border: Color(0xFFE4E8F0),
    text: Color(0xFF16202E),
    muted: Color(0xFF6B7A90),
    userBubble: Color(0xFF2A78D6),
    userBubbleText: Colors.white,
    botBubble: Colors.white,
    botBubbleText: Color(0xFF16202E),
    agentBubble: Color(0xFFFFF4E5),
    agentBubbleText: Color(0xFF16202E),
  );

  static const BanimarkTheme dark = BanimarkTheme(
    primary: Color(0xFF4F8FE0),
    onPrimary: Colors.white,
    background: Color(0xFF0F1420),
    surface: Color(0xFF181F2E),
    border: Color(0xFF283147),
    text: Color(0xFFE8ECF4),
    muted: Color(0xFF8A96AC),
    userBubble: Color(0xFF4F8FE0),
    userBubbleText: Colors.white,
    botBubble: Color(0xFF1F2839),
    botBubbleText: Color(0xFFE8ECF4),
    agentBubble: Color(0xFF3A2C14),
    agentBubbleText: Color(0xFFF3E7D2),
  );

  /// Match your app's Material colour scheme in one line.
  factory BanimarkTheme.fromScheme(ColorScheme s) => BanimarkTheme(
        primary: s.primary,
        onPrimary: s.onPrimary,
        background: s.surface,
        surface: s.surfaceContainerHighest,
        border: s.outlineVariant,
        text: s.onSurface,
        muted: s.onSurfaceVariant,
        userBubble: s.primary,
        userBubbleText: s.onPrimary,
        botBubble: s.surfaceContainerHighest,
        botBubbleText: s.onSurface,
        agentBubble: s.tertiaryContainer,
        agentBubbleText: s.onTertiaryContainer,
        danger: s.error,
      );

  BanimarkTheme copyWith({
    Color? primary, Color? onPrimary, Color? background, Color? surface, Color? border, Color? text, Color? muted,
    Color? userBubble, Color? userBubbleText, Color? botBubble, Color? botBubbleText, Color? agentBubble, Color? agentBubbleText,
    Color? danger, double? bubbleRadius, double? inputRadius, TextStyle? messageStyle, TextStyle? titleStyle, bool? compact,
    String? title, String? subtitle, String? agentSubtitle, String? closedSubtitle, String? placeholder, String? thinkingLabel, String? agentTypingLabel,
    String? handoverLabel, String? guestTitle, String? guestHint, String? guestNameLabel, String? guestEmailLabel,
    String? guestButton, String? retryLabel, String? loadEarlierLabel, String? greeting, Widget? avatar, Widget? botAvatar, Widget? agentAvatar, IconData? sendIcon,
    String? deleteTitle, String? deleteBody, String? deleteButton, String? cancelLabel, String? deletedNotice,
  }) =>
      BanimarkTheme(
        primary: primary ?? this.primary, onPrimary: onPrimary ?? this.onPrimary, background: background ?? this.background,
        surface: surface ?? this.surface, border: border ?? this.border, text: text ?? this.text, muted: muted ?? this.muted,
        userBubble: userBubble ?? this.userBubble, userBubbleText: userBubbleText ?? this.userBubbleText,
        botBubble: botBubble ?? this.botBubble, botBubbleText: botBubbleText ?? this.botBubbleText,
        agentBubble: agentBubble ?? this.agentBubble, agentBubbleText: agentBubbleText ?? this.agentBubbleText,
        danger: danger ?? this.danger, bubbleRadius: bubbleRadius ?? this.bubbleRadius, inputRadius: inputRadius ?? this.inputRadius,
        messageStyle: messageStyle ?? this.messageStyle, titleStyle: titleStyle ?? this.titleStyle,
        compact: compact ?? this.compact,
        title: title ?? this.title, subtitle: subtitle ?? this.subtitle, agentSubtitle: agentSubtitle ?? this.agentSubtitle,
        closedSubtitle: closedSubtitle ?? this.closedSubtitle, placeholder: placeholder ?? this.placeholder,
        thinkingLabel: thinkingLabel ?? this.thinkingLabel, agentTypingLabel: agentTypingLabel ?? this.agentTypingLabel, handoverLabel: handoverLabel ?? this.handoverLabel,
        guestTitle: guestTitle ?? this.guestTitle, guestHint: guestHint ?? this.guestHint, guestNameLabel: guestNameLabel ?? this.guestNameLabel,
        guestEmailLabel: guestEmailLabel ?? this.guestEmailLabel, guestButton: guestButton ?? this.guestButton,
        retryLabel: retryLabel ?? this.retryLabel, loadEarlierLabel: loadEarlierLabel ?? this.loadEarlierLabel, greeting: greeting ?? this.greeting,
        avatar: avatar ?? this.avatar, botAvatar: botAvatar ?? this.botAvatar, agentAvatar: agentAvatar ?? this.agentAvatar,
        sendIcon: sendIcon ?? this.sendIcon,
        deleteTitle: deleteTitle ?? this.deleteTitle, deleteBody: deleteBody ?? this.deleteBody,
        deleteButton: deleteButton ?? this.deleteButton, cancelLabel: cancelLabel ?? this.cancelLabel,
        deletedNotice: deletedNotice ?? this.deletedNotice,
      );
}
