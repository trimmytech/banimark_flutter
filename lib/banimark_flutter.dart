/// Banimark for Flutter: a fully themeable chat screen plus the small API
/// client behind it, for any app whose backend runs a Banimark support desk.
///
/// Quick start:
/// ```dart
/// BanimarkChat(
///   config: BanimarkConfig.laravel('https://yourapp.com'),
///   visitor: BanimarkVisitor(name: 'Ada', email: 'ada@acme.test'),
/// )
/// ```
library banimark_flutter;

export 'src/config.dart';
export 'src/models.dart';
export 'src/client.dart';
export 'src/controller.dart';
export 'src/theme.dart';
export 'src/appearance.dart';
export 'src/markdown.dart';
export 'src/chat_widget.dart';
export 'src/launcher.dart';
export 'src/tour.dart';
