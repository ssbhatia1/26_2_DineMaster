import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_token_storage.dart';

Future<dynamic> sendNetworkRequest(
  String url,
  Map<String, dynamic> body,
) async {
  final prefs = await SharedPreferences.getInstance();

  final token =
      await AuthTokenStorage.readAccessToken() ??
      prefs.getString('token') ??
      prefs.getString('flutter.token');

  final headers = <String, String>{
    'Accept': 'application/json',
    'Content-Type': 'application/json',
      };

  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }

  final response = await http
      .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
      .timeout(const Duration(seconds: 10));

  if (response.statusCode != 200) {
    throw Exception('Server error (${response.statusCode}): ${response.body}');
  }

  return jsonDecode(response.body);
}
