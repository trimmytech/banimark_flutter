## 0.2.2

- **The keyboard no longer covers the message box.** The chat lifts itself
  above the keyboard wherever it sits - the launcher's bottom sheet, a dialog,
  a tab. Inside a Scaffold that already resizes, nothing changes.
- **The message box takes several lines.** Enter starts a new line; the send
  button sends. It grows to six lines, then scrolls.
- **No spinner on the send button.** While a reply is on its way the typing
  dots say so; the button just dims until it arrives.
- **No colour flash when the chat opens.** The desk's look is kept - in memory
  for this run and on the device for the next - so the chat and the launcher
  paint in the desk's colours from the first frame. On the very first open
  the chat waits for the look instead of showing the default colours first.
  New: `BanimarkAppearance.cached(config)` and `BanimarkAppearance.stored(config)`.
- Deleting a conversation on a desk that does not have the route (an older
  Banimark, or a Laravel route cache from before its update) now says
  "not available on this support desk yet" instead of "try again".

## 0.2.1

- **Android builds on API 36 again.** `file_picker` moves to `^10.3.3`, which
  compiles against Flutter's `compileSdkVersion` instead of a hardcoded 34;
  8.x failed `checkDebugAarMetadata` once `flutter_plugin_android_lifecycle`
  started requiring compileSdk 36.

## 0.2.0

- **`BanimarkLauncher(navigatorKey: ...)`** - needed when the bubble wraps the
  whole app through `MaterialApp.builder`, which sits above the Navigator:
  without it the tap had nowhere to open the chat (found by the test app).
  Give the same key to `MaterialApp(navigatorKey: ...)`. Wrapping a single
  screen needs nothing.

- **The visitor can delete their conversation.** A bin in the header (shown
  once there is a conversation) asks first, then clears the chat and starts
  over; `BanimarkController.deleteConversation()` and
  `BanimarkClient.deleteConversation()` do the same for your own UI. The desk
  keeps it for the team until it is erased (30 days by default). The dialog's
  words are on `BanimarkTheme` (`deleteTitle`, `deleteBody`, `deleteButton`,
  `cancelLabel`, `deletedNotice`). Needs a desk on 0.30.10 or newer.

- **A floating chat bubble: `BanimarkLauncher`.** Wrap a screen and you get the
  website widget's launcher in the app: an unread count for replies from the
  team (9+ past nine) that keeps counting while the chat is closed, dragging
  anywhere with the spot remembered on the device, and a small × that puts it
  away - it returns after the desk's "bring it back after" minutes (or
  `reappearAfter:`; zero = until the app is opened again) and at once when a
  reply arrives. Hidden on a desk that is not activated yet.
- **Unread survives a restart.** The controller remembers the last reply the
  visitor read (`<storageKey>_seen`) and a restored thread counts what came
  after it; `markRead()` records it. A visitor from before this sees nothing
  as new the first time.
- **Two paces of polling.** `BanimarkController.setActive(bool)`: on screen,
  the desk's "check for replies every" seconds (the heartbeat staff see); off
  screen, its "while closed, check every" seconds (`idlePollEvery`, 30 s
  until the desk says). `BanimarkAppearance` now carries `pollEvery`,
  `idlePollEvery` and `reappearAfter`; `BanimarkChat` on its own is unchanged.

- **The app follows more of the owner's Widget page** (with
  `followAdminAppearance: true`): the line under the title, the "back at 9:00"
  note out of hours (it wins over that line, as on the website), the header
  logo (resolved against the endpoint, so a standalone desk's path works; a
  picture that fails to load puts the chat glyph back), the corner style
  (`soft` / `square` set the bubble and input radii; `rounded` keeps yours),
  compact spacing (new `BanimarkTheme.compact`) and the reply chime - a system
  alert sound on a team reply unless the owner turned the chime off. An
  out-of-hours greeting needs nothing here: the desk sends it as `greeting`.
  Launcher, auto-open and page rules are website-only and are ignored.

## 0.1.1

- **Fix: a message the desk refused was not marked as failed.** Only a network
  or server error (an exception) flipped the bubble; a `{"ok": false}` answer -
  "that message is too long", a flood limit - left it looking delivered, with
  no retry. The bubble now carries the verdict either way, so anything that did
  not go through can be sent again. Matches the web widget and the chat link,
  which gained the same Retry affordance in Banimark 0.16.1.

## 0.1.0

- First release: `BanimarkChat` widget, `BanimarkController`, `BanimarkClient`, `BanimarkTheme`.
- Session resume, human handover with polling, guest form, retry on failure.
