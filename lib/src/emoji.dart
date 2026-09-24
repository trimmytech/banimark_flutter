import 'package:flutter/material.dart';

import 'theme.dart';

/// A small emoji keyboard, built in - no extra dependency, and the same
/// curated set the web widget offers so both sides of a conversation see the
/// characters they expect.
class BanimarkEmojiPicker extends StatefulWidget {
  final BanimarkTheme theme;
  final ValueChanged<String> onPick;
  const BanimarkEmojiPicker({super.key, required this.theme, required this.onPick});

  static const groups = <String, String>{
    'Smileys': '😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 😉 😊 😇 🥰 😍 🤩 😘 😋 😛 😜 🤪 🤗 🤭 🤔 😐 😑 😶 😏 🙄 😬 😌 😔 😪 😴 😷 🤒 🤢 🥵 🥶 😵 🤯 🥳 😎 🤓 🧐 😕 😟 🙁 😮 😲 🥺 😨 😰 😢 😭 😱 😖 😞 😩 😫 🥱 😤 😡',
    'Gestures': '👍 👎 👌 ✌️ 🤞 🤙 👈 👉 👆 👇 ☝️ ✋ 👋 🤝 🙏 ✊ 👊 👏 🙌 👐 💪 🫶 ✍️',
    'Objects': '📎 📁 📄 📋 📌 ✂️ 🔒 🔑 🔧 ⚙️ 🔗 💡 🛒 💳 💰 🧾 📦 ✉️ 📧 📱 💻 🖥️ 📷 🔔 ⏰ ⌛ 📅 📊 📈 📉',
    'Symbols': '✅ ☑️ ✔️ ❌ ⭕ 🚫 ⚠️ ❗ ❓ 💬 ♻️ 🔄 ➡️ ⬅️ ⭐ ✨ ⚡ 🔥 💥 💯 🎉 🎊 🎁 🏆 ❤️ 🧡 💛 💚 💙 💜 🖤 💔 💕 👀 🧠',
    'Nature': '🐶 🐱 🐭 🐰 🦊 🐻 🐼 🐨 🦁 🐮 🐷 🐸 🐔 🐧 🦉 🌵 🌲 🌴 🌱 🍀 🌸 🌻 🌹 🌍 🌙 ☀️ ⛅ 🌧️ ❄️ 🌈 💧 🌊 🍎 🍋 🍓 🍕 🍔 ☕ 🍺 🎂',
  };

  @override
  State<BanimarkEmojiPicker> createState() => _BanimarkEmojiPickerState();
}

class _BanimarkEmojiPickerState extends State<BanimarkEmojiPicker> {
  int _group = 0;

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final names = BanimarkEmojiPicker.groups.keys.toList();
    final list = BanimarkEmojiPicker.groups[names[_group]]!.split(' ').where((e) => e.isNotEmpty).toList();
    return Container(
      height: 258,
      decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.border))),
      child: Column(
        children: [
          SizedBox(
            height: 42,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              itemCount: names.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => setState(() => _group = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == _group ? t.background : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(BanimarkEmojiPicker.groups[names[i]]!.split(' ').first, style: const TextStyle(fontSize: 18)),
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: t.border),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 46, mainAxisSpacing: 2, crossAxisSpacing: 2),
              itemCount: list.length,
              itemBuilder: (_, i) => InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => widget.onPick(list[i]),
                child: Center(child: Text(list[i], style: const TextStyle(fontSize: 24))),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
