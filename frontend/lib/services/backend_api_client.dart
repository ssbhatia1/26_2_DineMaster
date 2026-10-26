import 'package:flutter/foundation.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class BackendApiException implements Exception {
  final int statusCode;
  final String message;

  const BackendApiException(this.statusCode, this.message);

  @override
  String toString() => 'Backend API error ($statusCode): $message';
}

class BackendApiClient {
  const BackendApiClient();

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

    return Uri.parse('$baseUrl$path');
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
    final token = prefs.getString('token') ?? prefs.getString('flutter.token');
    debugPrint('AUTH CHECK: token found = ${token != null && token.isNotEmpty}');

    final headers = <String, String>{
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };

    final request = http.Request(method, await _uri(path))
      ..headers.addAll(headers);

    if (body != null) {
      request.body = jsonEncode(body);
    }

    final streamedResponse = await http.Client().send(request).timeout(
      const Duration(seconds: 10),
    );

    final response = await http.Response.fromStream(streamedResponse);

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

