import 'dart:convert';
import '../platform/io.dart';

Future<dynamic> sendNetworkRequest(
  String url,
  Map<String, dynamic> body,
) async {
  final client = HttpClient();

  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.set('content-type', 'application/json');
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
