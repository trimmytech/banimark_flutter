import 'package:banimark_flutter/banimark_flutter.dart';
import 'package:flutter/material.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFF2A78D6), useMaterial3: true),
        // the floating bubble over the whole app: unread count, draggable, dismissible
        builder: (context, child) => BanimarkLauncher(
          config: BanimarkConfig.laravel('http://127.0.0.1:8001', token: null),
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('My app')),
          body: const Center(child: Text('Tap the bubble, or the button, to talk to support')),
          floatingActionButton: Builder(
            builder: (context) => FloatingActionButton.extended(
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Support'),
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (_) => FractionallySizedBox(
                  heightFactor: .92,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                    child: BanimarkChat(
                      // Laravel host: https://yourapp.com ; standalone: the banimark.php URL
                      config: BanimarkConfig.laravel('http://127.0.0.1:8001', token: null),
                      // For signed-in users mint a VisitorToken server-side and pass it as
                      // `token:` - the AI's tools then scope rows to this user. Guests get a form.
                      theme: BanimarkTheme.fromScheme(Theme.of(context).colorScheme).copyWith(
                        title: 'AidaSuite Support',
                        subtitle: 'We usually reply in under a minute',
                      ),
                      onClose: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
