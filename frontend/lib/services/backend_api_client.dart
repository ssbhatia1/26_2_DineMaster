import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_token_storage.dart';

class BackendApiException implements Exception {
  final int statusCode;
  final String message;

  const BackendApiException(this.statusCode, this.message);

  @override
  String toString() => 'Backend API error ($statusCode): $message';
}

class BackendApiClient {
  const BackendApiClient();

  static Future<bool>? _refreshInFlight;

  Future<Uri> _uri(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final configuredBaseUrl = prefs.getString('backend_api_url')?.trim();
    final isServer = prefs.getBool('is_server') ?? true;
    final serverIp = prefs.getString('server_ip')?.trim();

    final fallbackHost = !isServer && serverIp != null && serverIp.isNotEmpty
        ? serverIp
        : 'localhost';

    final baseUrl = configuredBaseUrl == null || configuredBaseUrl.isEmpty
        ? 'http://$fallbackHost:8081'
        : configuredBaseUrl.replaceFirst(RegExp(r'/$'), '');

    final normalizedPath =
        path.startsWith('/api/') &&
            !path.startsWith('/api/v1/') &&
            path != '/api/health'
        ? '/api/v1${path.substring(4)}'
        : path;

    return Uri.parse('$baseUrl$normalizedPath');
  }

  Future<dynamic> getJson(String path) async {
    return _requestJson('GET', path);
  }

  Future<dynamic> postJson(String path, Map<String, dynamic> body) async {
    return _requestJson('POST', path, body: body);
  }

  Future<dynamic> putJson(String path, Map<String, dynamic> body) async {
    return _requestJson('PUT', path, body: body);
  }

  Future<dynamic> patchJson(String path, Map<String, dynamic> body) async {
    return _requestJson('PATCH', path, body: body);
  }

  Future<void> delete(String path) async {
    await _requestJson('DELETE', path);
  }

  Future<dynamic> _requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var token = await AuthTokenStorage.readAccessToken();
    // Migrate tokens from older releases once, then remove the insecure copy.
    if (token == null || token.isEmpty) {
      token = prefs.getString('token') ?? prefs.getString('flutter.token');
      if (token != null && token.isNotEmpty) {
        await AuthTokenStorage.save(accessToken: token);
        await prefs.remove('token');
        await prefs.remove('flutter.token');
      }
    }

    final response = await _send(method, path, body, token);
    if (response.statusCode == 401 &&
        !path.endsWith('/auth/login') &&
        !path.endsWith('/auth/refresh')) {
      final refreshToken = await AuthTokenStorage.readRefreshToken();
      if (refreshToken != null && await _refreshOnce(refreshToken)) {
        return _decodeResponse(
          await _send(
            method,
            path,
            body,
            await AuthTokenStorage.readAccessToken(),
          ),
        );
      }
      await AuthTokenStorage.clear();
    }
    return _decodeResponse(response);
  }

  Future<http.Response> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
    String? token,
  ) async {
    final headers = <String, String>{
      'Accept': 'application/json',
            if (body != null) 'Content-Type': 'application/json',
    };

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final request = http.Request(method, await _uri(path))
      ..headers.addAll(headers);

    if (body != null) {
      request.body = jsonEncode(body);
    }

    final client = http.Client();
    try {
      final streamedResponse = await client
          .send(request)
          .timeout(const Duration(seconds: 10));
      return await http.Response.fromStream(streamedResponse);
    } finally {
      client.close();
    }
  }

  Future<bool> _refresh(String refreshToken) async {
    final response = await _send('POST', '/api/v1/auth/refresh', {
      'refreshToken': refreshToken,
    }, null);
    if (response.statusCode < 200 || response.statusCode >= 300) return false;
    final data = jsonDecode(response.body);
    if (data is! Map) return false;
    await AuthTokenStorage.save(
      accessToken: (data['accessToken'] ?? data['token'])?.toString(),
      refreshToken: data['refreshToken']?.toString(),
    );
    return true;
  }

  Future<bool> _refreshOnce(String refreshToken) {
    final activeRefresh = _refreshInFlight;
    if (activeRefresh != null) return activeRefresh;
    final pending = _refresh(refreshToken);
    _refreshInFlight = pending;
    return pending.whenComplete(() => _refreshInFlight = null);
  }

  dynamic _decodeResponse(http.Response response) {
    dynamic decoded;
    if (response.body.trim().isNotEmpty) {
      decoded = jsonDecode(response.body);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error']?.toString() ?? response.body
          : response.body;

      throw BackendApiException(response.statusCode, message);
    }

    return decoded;
  }
}
