import 'package:flutter_test/flutter_test.dart';
import 'package:specular/src/platform/platform_capabilities.dart';
import 'package:specular/src/ui/screens.dart';

void main() {
  test('macOS exposes only supported desktop integrations', () {
    final macos = PlatformCapabilities.forPlatform(SpecularPlatform.macos);

    expect(macos.isDesktop, isTrue);
    expect(macos.supportsHomeWidget, isFalse);
    expect(macos.supportsCameraImport, isFalse);
    expect(macos.supportsDurableBackgroundSync, isFalse);
    expect(macos.supportsForegroundRecording, isFalse);
    expect(macos.supportsBestEffortInProcessSync, isTrue);
    expect(editorImageActions(macos), [EditorImageAction.gallery]);
    expect(
      syncScheduleDescription(macos),
      contains('does not run after you quit'),
    );
  });

  test('Android retains its existing camera and durable-work capabilities', () {
    final android = PlatformCapabilities.forPlatform(SpecularPlatform.android);

    expect(android.supportsHomeWidget, isTrue);
    expect(android.supportsCameraImport, isTrue);
    expect(android.supportsDurableBackgroundSync, isTrue);
    expect(android.supportsForegroundRecording, isTrue);
    expect(editorImageActions(android), [
      EditorImageAction.camera,
      EditorImageAction.gallery,
    ]);
    expect(syncScheduleDescription(android), contains('Android permits'));
  });
}
