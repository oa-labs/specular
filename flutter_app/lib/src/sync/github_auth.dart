import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

/// Browser-based GitHub authorization for the guided backup setup.
///
/// The OAuth application is a public native client. PKCE and a one-time state
/// value protect the callback; the GitHub client configuration is supplied at
/// build time rather than checked in with the app source.
class GitHubAuthorizationService {
  GitHubAuthorizationService(
    this._storage, {
    Dio? dio,
    String? clientId,
    String? clientSecret,
  }) : _dio = dio ?? Dio(),
       _clientId =
           clientId ?? const String.fromEnvironment('GITHUB_OAUTH_CLIENT_ID'),
       _clientSecret =
           clientSecret ??
           const String.fromEnvironment('GITHUB_OAUTH_CLIENT_SECRET');

  static const _stateKey = 'github_oauth_pending_state';
  static const _verifierKey = 'github_oauth_pending_verifier';
  static const _createdKey = 'github_oauth_pending_created_at';
  static const _callback = 'specular://oauth';

  final FlutterSecureStorage _storage;
  final Dio _dio;
  final String _clientId;
  final String _clientSecret;

  bool get isConfigured => _clientId.isNotEmpty;

  Future<String> authorize() async {
    if (!isConfigured) {
      throw StateError(
        'GitHub sign-in is not available in this build. Use a personal access token instead.',
      );
    }
    final state = _randomUrlValue(24);
    final verifier = _randomUrlValue(48);
    await Future.wait([
      _storage.write(key: _stateKey, value: state),
      _storage.write(key: _verifierKey, value: verifier),
      _storage.write(
        key: _createdKey,
        value: DateTime.now().toUtc().toIso8601String(),
      ),
    ]);
    try {
      final challenge = base64Url
          .encode(sha256.convert(utf8.encode(verifier)).bytes)
          .replaceAll('=', '');
      final authorization = Uri.https('github.com', '/login/oauth/authorize', {
        'client_id': _clientId,
        'redirect_uri': _callback,
        'scope': 'repo',
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      });
      final callback = await FlutterWebAuth2.authenticate(
        url: authorization.toString(),
        callbackUrlScheme: 'specular',
      );
      final returned = Uri.parse(callback);
      if (returned.queryParameters['error'] != null) {
        throw StateError(
          returned.queryParameters['error_description'] ??
              'GitHub authorization was cancelled.',
        );
      }
      final savedState = await _storage.read(key: _stateKey);
      final savedVerifier = await _storage.read(key: _verifierKey);
      final created = DateTime.tryParse(
        await _storage.read(key: _createdKey) ?? '',
      );
      if (savedState == null ||
          savedVerifier == null ||
          returned.queryParameters['state'] != savedState ||
          created == null ||
          DateTime.now().toUtc().difference(created.toUtc()).inMinutes > 10) {
        throw StateError(
          'GitHub sign-in expired or could not be verified. Try again.',
        );
      }
      final code = returned.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw StateError('GitHub did not return an authorization code.');
      }
      final response = await _dio.post<Map<String, dynamic>>(
        'https://github.com/login/oauth/access_token',
        data: {
          'client_id': _clientId,
          if (_clientSecret.isNotEmpty) 'client_secret': _clientSecret,
          'code': code,
          'redirect_uri': _callback,
          'code_verifier': savedVerifier,
        },
        options: Options(
          headers: const {'Accept': 'application/json'},
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      final token = response.data?['access_token']?.toString();
      if (token == null || token.isEmpty) {
        throw StateError(
          response.data?['error_description']?.toString() ??
              'GitHub sign-in failed.',
        );
      }
      return token;
    } finally {
      await Future.wait([
        _storage.delete(key: _stateKey),
        _storage.delete(key: _verifierKey),
        _storage.delete(key: _createdKey),
      ]);
    }
  }

  String _randomUrlValue(int bytes) {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(bytes, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}
