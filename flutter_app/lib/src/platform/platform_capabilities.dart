import 'dart:io';

/// Features whose implementation is intentionally different between the
/// Android client and the macOS desktop app. Keeping this in one place makes
/// platform decisions visible at call sites and easy to exercise in tests.
enum SpecularPlatform { android, macos, other }

class PlatformCapabilities {
  const PlatformCapabilities({
    required this.platform,
    required this.supportsHomeWidget,
    required this.supportsCameraImport,
    required this.supportsDurableBackgroundSync,
    required this.supportsForegroundRecording,
    required this.supportsPortableBackupDocuments,
  });

  final SpecularPlatform platform;
  final bool supportsHomeWidget;
  final bool supportsCameraImport;
  final bool supportsDurableBackgroundSync;
  final bool supportsForegroundRecording;
  final bool supportsPortableBackupDocuments;

  bool get isDesktop => platform == SpecularPlatform.macos;

  /// macOS scheduling is a timer owned by the running application. It is
  /// deliberately not advertised as work that survives quitting the app.
  bool get supportsBestEffortInProcessSync => isDesktop;

  static PlatformCapabilities get current => forPlatform(
    Platform.isAndroid
        ? SpecularPlatform.android
        : Platform.isMacOS
        ? SpecularPlatform.macos
        : SpecularPlatform.other,
  );

  static PlatformCapabilities forPlatform(SpecularPlatform platform) {
    switch (platform) {
      case SpecularPlatform.android:
        return const PlatformCapabilities(
          platform: SpecularPlatform.android,
          supportsHomeWidget: true,
          supportsCameraImport: true,
          supportsDurableBackgroundSync: true,
          supportsForegroundRecording: true,
          supportsPortableBackupDocuments: true,
        );
      case SpecularPlatform.macos:
        return const PlatformCapabilities(
          platform: SpecularPlatform.macos,
          supportsHomeWidget: false,
          supportsCameraImport: false,
          supportsDurableBackgroundSync: false,
          supportsForegroundRecording: false,
          supportsPortableBackupDocuments: false,
        );
      case SpecularPlatform.other:
        return const PlatformCapabilities(
          platform: SpecularPlatform.other,
          supportsHomeWidget: false,
          supportsCameraImport: false,
          supportsDurableBackgroundSync: false,
          supportsForegroundRecording: false,
          supportsPortableBackupDocuments: false,
        );
    }
  }
}
