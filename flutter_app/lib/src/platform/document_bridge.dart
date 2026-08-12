import 'package:flutter/services.dart';

/// Android system-document picker bridge used for portable backups. The native
/// side copies between a granted content URI and an app-private temporary file.
class DocumentBridge {
  static const _channel = MethodChannel('com.specular.android/documents');

  Future<String?> createBackupDocument() => _channel.invokeMethod<String>(
    'createBackupDocument',
    {'name': 'specular-backup.zip'},
  );

  Future<String?> openBackupDocument() =>
      _channel.invokeMethod<String>('openBackupDocument');

  Future<void> writeDocument({
    required String uri,
    required String sourcePath,
  }) => _channel.invokeMethod<void>('writeDocument', {
    'uri': uri,
    'sourcePath': sourcePath,
  });

  Future<void> readDocument({
    required String uri,
    required String destinationPath,
  }) => _channel.invokeMethod<void>('readDocument', {
    'uri': uri,
    'destinationPath': destinationPath,
  });
}
