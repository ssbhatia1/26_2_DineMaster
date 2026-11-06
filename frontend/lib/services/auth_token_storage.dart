import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokenStorage {
  AuthTokenStorage._();

  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'dinemaster.access_token';
  static const _refreshKey = 'dinemaster.refresh_token';

  static Future<String?> readAccessToken() => _storage.read(key: _accessKey);
  static Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  static Future<void> save({String? accessToken, String? refreshToken}) async {
    if (accessToken != null && accessToken.isNotEmpty) {
      await _storage.write(key: _accessKey, value: accessToken);
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _refreshKey, value: refreshToken);
    }
  }

  static Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
