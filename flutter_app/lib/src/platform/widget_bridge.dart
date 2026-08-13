import 'package:flutter/services.dart';

import 'platform_capabilities.dart';

/// Best-effort notification for the Android home-screen widget. Desktop has
/// no equivalent in this release, so these calls are deliberate no-ops there.
class WidgetBridge {
  static const _channel = MethodChannel('com.specular.android/widget');

  static void setNavigationHandler(void Function(String route) handler) {
    if (!PlatformCapabilities.current.supportsHomeWidget) return;
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
    if (!PlatformCapabilities.current.supportsHomeWidget) return;
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
