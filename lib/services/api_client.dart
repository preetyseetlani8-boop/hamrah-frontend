import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../screens/login_screen.dart';
import 'UserSession.dart';

class ApiClient {
  ApiClient._();

  static Map<String, dynamic> decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      if (decoded is List) return {'data': decoded};
    } catch (_) {}
    return {'message': response.body};
  }

  static bool isSuccess(int statusCode) =>
      statusCode >= 200 && statusCode < 300;

  static void ensureSuccess(http.Response response, [Map<String, dynamic>? data]) {
    if (response.statusCode == 401) {
      UserSession.clear();
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const HamrahLoginPage(
            sessionMessage: 'Session expired. Please log in again.',
          ),
        ),
        (route) => false,
      );
      throw Exception('Session expired');
    }
    if (!isSuccess(response.statusCode)) {
      final msg = data?['message']?.toString() ?? response.body;
      throw Exception(msg.isEmpty ? 'Request failed (${response.statusCode})' : msg);
    }
  }

  static Future<Map<String, dynamic>> sendMultipart(
    http.MultipartRequest request, {
    bool requireAuth = false,
  }) async {
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = decode(response);
    ensureSuccess(response, data);
    return data;
  }
}
