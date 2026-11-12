import 'dart:convert';
import '../platform/io.dart';
import '../../services/auth_token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<dynamic> sendNetworkRequest(
  String url,
  Map<String, dynamic> body,
) async {
  final client = HttpClient();

  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.set('content-type', 'application/json');
    final prefs = await SharedPreferences.getInstance();
    final token = await AuthTokenStorage.readAccessToken() ??
        prefs.getString('token') ??
        prefs.getString('flutter.token');
    if (token != null && token.isNotEmpty) {
      request.headers.set('authorization', 'Bearer $token');
    }
    request.write(jsonEncode(body));

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw Exception('Server error: $responseBody');
    }

    return jsonDecode(responseBody);
  } finally {
    client.close();
  }
}
