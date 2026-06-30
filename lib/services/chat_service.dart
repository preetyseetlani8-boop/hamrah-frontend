import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'api_client.dart';

class ChatService {
  ChatService._();

  /// GET /chat/{ride_id}/messages
  static Future<List<Map<String, dynamic>>> fetchMessages({
    required String rideId,
  }) async {
    final response = await http.get(
      ApiConfig.uri('/chat/$rideId/messages'),
      headers: ApiConfig.jsonHeaders(),
    );

    ApiClient.ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return [];

    return decoded.map<Map<String, dynamic>>((m) {
      return {
        'text':   m['text'] ?? '',
        'fromMe': m['from_me'] == true,
        'time':   m['time'] ?? '',
        'sender': m['sender_name'] ?? '',
      };
    }).toList();
  }

  /// POST /chat/send
  static Future<Map<String, dynamic>> sendMessage({
    required String rideId,
    required String text,
  }) async {
    final response = await http.post(
      ApiConfig.uri('/chat/send'),
      headers: ApiConfig.jsonHeaders(),
      body: jsonEncode({
        'ride_id': int.tryParse(rideId) ?? 0,
        'message': text,
      }),
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    return data;
  }
}
