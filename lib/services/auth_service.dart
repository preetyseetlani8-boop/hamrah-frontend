import 'dart:convert';
import 'UserSession.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'api_client.dart';

class AuthService {
  /// POST /api/auth/login
  /// Expected response: { "success": true, "token": "...", "user": { ... }, "roles": ["passenger"] }
  static Future<Map<String, dynamic>> login(
    String emailOrUsername,
    String password,
  ) async {
    final response = await http.post(
      ApiConfig.uri(ApiConfig.login),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'username': emailOrUsername,
        'password': password,
      },
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    return data;
  }

  /// POST /api/auth/register
  static Future<Map<String, dynamic>> signup(
    String name,
    String email,
    String password, {
    String role = 'passenger',
  }) async {
    final response = await http.post(
      ApiConfig.uri(ApiConfig.register),
      headers: ApiConfig.jsonHeaders(includeAuth: false),
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'role': role,
      }),
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    return data;
  }

  /// POST /password/forgot
  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final response = await http.post(
      ApiConfig.uri(ApiConfig.forgotPassword),
      headers: ApiConfig.jsonHeaders(includeAuth: false),
      body: jsonEncode({'email': email}),
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    return data;
  }

  /// POST /password/verify-otp
  static Future<Map<String, dynamic>> verifyForgotPasswordOtp({
    required String email,
    required String otp,
  }) async {
    final response = await http.post(
      ApiConfig.uri(ApiConfig.forgotPasswordVerifyOtp),
      headers: ApiConfig.jsonHeaders(includeAuth: false),
      body: jsonEncode({'email': email, 'otp_code': otp}),
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    return data;
  }

  /// POST /password/reset
  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final response = await http.post(
      ApiConfig.uri(ApiConfig.resetPassword),
      headers: ApiConfig.jsonHeaders(includeAuth: false),
      body: jsonEncode({
        'email': email,
        'otp_code': otp,
        'new_password': newPassword,
      }),
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    return data;
  }

  /// PATCH /users/profile
  static Future<void> updateProfile({
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    final response = await http.patch(
      ApiConfig.uri('/users/profile'),
      headers: ApiConfig.jsonHeaders(),
      body: jsonEncode({
        'first_name':   firstName,
        'last_name':    lastName,
        'phone_number': phone,
      }),
    );
    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
  }

  /// PATCH /users/switch-mode
  static Future<void> switchMode(String mode) async {
    final response = await http.patch(
      ApiConfig.uri('/users/switch-mode'),
      headers: ApiConfig.jsonHeaders(),
      body: jsonEncode({'mode': mode}),
    );
    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
  }

  /// POST /users/enable_passenger — driver-only account gets passenger role
  static Future<void> enablePassenger() async {
    final response = await http.post(
      ApiConfig.uri('/users/enable_passenger'),
      headers: ApiConfig.jsonHeaders(),
    );
    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
  }

  /// GET /users/me
  static Future<Map<String, dynamic>> fetchMe() async {
    final response = await http.get(
      ApiConfig.uri(ApiConfig.me),
      headers: ApiConfig.jsonHeaders(includeAuth: true),
    );
    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    return data;
  }

  /// Refresh roles, profile, vehicles, and ride stats from /users/me.
  static Future<void> syncSessionFromMe() async {
    final me = await fetchMe();
    UserSession.name =
        '${me['first_name'] ?? ''} ${me['last_name'] ?? ''}'.trim();
    UserSession.studentId = me['dsu_reg_id']?.toString() ?? '';
    UserSession.phone = me['phone_number']?.toString() ?? '';
    UserSession.email = me['email']?.toString() ?? '';
    UserSession.totalRides = me['total_rides'] as int? ?? 0;

    UserSession.registeredRoles = [];
    if (me['is_passenger'] == true) {
      UserSession.registeredRoles.add('passenger');
    }
    if (me['is_driver'] == true) {
      UserSession.registeredRoles.add('driver');
    }

    final vehicles = me['vehicles'] as List?;
    if (vehicles != null && vehicles.isNotEmpty) {
      final car = vehicles.firstWhere(
        (v) => v['mode_of_transport'] == 'car',
        orElse: () => vehicles[0],
      );
      UserSession.vehicleId = car['id'] as int? ?? 0;
      UserSession.vehicleMode = car['mode_of_transport']?.toString() ?? '';
      UserSession.vehicleNumber = car['vehicle_number']?.toString() ?? '';
      UserSession.vehicleModel = car['vehicle_model']?.toString() ?? '';
      UserSession.vehicleColour = car['vehicle_colour']?.toString() ?? '';
    }

    await UserSession.save();
  }

  /// POST /api/auth/resend-otp
  static Future<Map<String, dynamic>> resendOtp({
    required String email,
    String role = 'passenger',
  }) async {
    final response = await http.post(
      ApiConfig.uri(ApiConfig.resendOtp),
      headers: ApiConfig.jsonHeaders(includeAuth: false),
      body: jsonEncode({'email': email, 'role': role}),
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    return data;
  }

  /// POST /api/auth/verify-otp
  static Future<Map<String, dynamic>> verifyOtp({
    required String email,
    required String otp,
    String role = 'passenger',
  }) async {
    final response = await http.post(
      ApiConfig.uri(ApiConfig.verifyOtp),
      headers: ApiConfig.jsonHeaders(includeAuth: false),
      body: jsonEncode({
        'email': email,
        'otp_code': otp,
      }),
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    return data;
  }
}
