import 'package:flutter/services.dart';

/// Best-effort notification for the Android home-screen widget. The widget
/// reads the same legacy SQLite index, so no Flutter process needs to remain
/// alive for it to render or complete a task.
class WidgetBridge {
  static const _channel = MethodChannel('com.specular.android/widget');

  static void setNavigationHandler(void Function(String route) handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'navigate') {
        final arguments = Map<Object?, Object?>.from(
          call.arguments as Map? ?? const {},
        );
        final route = arguments['route'] as String?;
        if (route != null) handler(route);
      }
    });
  }

  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod<void>('refreshTodoWidget');
    } on MissingPluginException {
      // Background isolates have no activity channel. The native worker/widget
      // will still refresh itself on its next scheduled update.
    } on PlatformException {
      // A launcher can reject an update while it is restoring widgets.
    }
  }
}
