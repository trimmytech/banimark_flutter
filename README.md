# banimark_flutter

A drop-in support chat for Flutter apps whose backend runs a **Banimark** AI support desk
(Laravel package or standalone). Same engine, same rules and tools as the web widget - now
native in your app, fully themeable, with human handover and offline-safe session resume.

## Install

Add to `pubspec.yaml` (path or git while private):

```yaml
dependencies:
  banimark_flutter:
    path: ../banimark_flutter
```

## Use

```dart
BanimarkChat(
  config: BanimarkConfig.laravel('https://yourapp.com'),   // or BanimarkConfig.standalone('https://yourapp.com/banimark.php')
  visitor: BanimarkVisitor(name: 'Ada', email: 'ada@acme.test'), // optional for guests
)
```

Put it in a route, a bottom sheet (see `example/`), or a tab. It sizes to its parent.

### The floating bubble

Or let the SDK put the website's launcher in your app - a chat bubble over any
screen (wrap the screen, or every screen through `MaterialApp.builder`):

```dart
BanimarkLauncher(
  config: BanimarkConfig.laravel('https://yourapp.com'),
  visitor: BanimarkVisitor(name: 'Ada', email: 'ada@acme.test'),
  child: MyHomeScreen(),
)
```

It shows how many replies from your team are unread (9+ past nine) even while
the chat is closed, polling at the interval the desk owner set on the Widget
page ("while the chat is closed, check every…"). The user can drag it anywhere
- the spot is remembered on the device - and close it with its small ×; it
comes back after the owner's "bring it back after" minutes (`reappearAfter:`
overrides; `Duration.zero` = not until the app is opened again), and straight
away when a reply arrives. Tapping it opens `BanimarkChat` in a bottom sheet;
pass `onOpen:` to open it your own way with the same controller.

Wrapping every screen through `MaterialApp.builder`? That spot is above the
app's Navigator, so give the launcher and the app the same key:

```dart
final nav = GlobalKey<NavigatorState>();
MaterialApp(
  navigatorKey: nav,
  builder: (context, child) => BanimarkLauncher(config: cfg, navigatorKey: nav, child: child!),
)
```

### First-run tour

Pass `showTour: true` (on `BanimarkChat` or `BanimarkLauncher`) and the first
time the chat opens on a device it points out the emoji, paperclip and send
buttons, one at a time. The delete bin is explained later, once there is a
conversation to delete. Each spot is shown once per device; `Skip` ends the
tour for good. Change the words on `BanimarkTheme` (`tourEmoji`, `tourAttach`,
`tourSend`, `tourDelete`, `tourNext`, `tourDone`, `tourSkip`), and call
`BanimarkChat.resetTour()` to show it again.

```dart
BanimarkLauncher(config: cfg, showTour: true, child: MyHomeScreen())
```

### Deleting a conversation

The header has a bin once a conversation exists: the visitor confirms, the
chat is cleared and starts fresh. On the desk it is a soft delete - the team
still sees it, marked, until it is erased (30 days by default, or never if they
keep it). Call `controller.deleteConversation()` from your own UI if you hide
the header.

### Signed-in users (recommended)

Your server mints a token with Banimark's `VisitorToken` (HMAC, contains e.g. `user_id`) and
hands it to the app - via your login response or a small endpoint. Pass it as `token:`.
The AI's tools then scope every database lookup to that user **server-side**; the app can
never widen it.

```dart
BanimarkConfig.laravel('https://yourapp.com', token: me.banimarkToken)
```

Without a token the widget runs in guest mode and asks for name + email first
(`askGuestDetails: false` to skip).

### Theming

Everything is on `BanimarkTheme` - colours, radii, avatar widgets, every string:

```dart
theme: BanimarkTheme.fromScheme(Theme.of(context).colorScheme).copyWith(
  title: 'Acme Support',
  subtitle: 'Typically replies in seconds',
  bubbleRadius: 14,
  avatar: Image.asset('assets/logo.png', width: 40),
  greeting: 'Hi! How can we help today?',
)
```

`BanimarkTheme.light` / `.dark` are ready-made; pass `bubbleBuilder` to replace bubbles entirely.

### Behaviour you get for free

- **Human handover**: when the AI escalates (or staff take over), the header switches to
  "You are chatting with a human", a banner appears and the widget polls for agent replies
  (`pollEvery`, default 4 s). The poll doubles as a presence heartbeat so staff see
  *online now* - and if the visitor leaves, Banimark emails them the reply instead.
- **Resume**: the session id is stored on device; reopening the chat replays the conversation.
  Call `controller.reset()` on logout.
- **Never crashes on the network**: failures show a friendly line and a tap-to-retry bubble.
- **Own UI?** Use `BanimarkController` (a `ChangeNotifier`) or `BanimarkClient` directly.

## Endpoints used

| Call | Laravel | Standalone |
|---|---|---|
| send | `POST /banimark/chat` | `POST {entry}/chat` |
| agent replies | `GET /banimark/chat/poll` | `GET {entry}/chat/poll` |
| resume | `GET /banimark/chat/history` | `GET {entry}/chat/history` |

## Requirements

Flutter 3.10+, Dart 3. Dependencies: `http`, `shared_preferences`.
