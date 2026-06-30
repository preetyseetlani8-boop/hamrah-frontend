import '../services/UserSession.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/login_screen.dart';
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();


class ApiConfig {
  ApiConfig._();
  static Dio createDio() {
    final dio = Dio(BaseOptions(baseUrl: baseUrl));
    dio.interceptors.add(_AuthInterceptor());
    return dio;
  }

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://bobcat-janitor-survival.ngrok-free.dev',
  );

  static Uri uri(String path, {Map<String, String>? query}) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final base = Uri.parse('$baseUrl$normalized');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: query);
  }

  static Map<String, String> jsonHeaders({bool includeAuth = true}) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (includeAuth && UserSession.token.isNotEmpty)
        'Authorization': 'Bearer ${UserSession.token}',
    };
  }

  static Map<String, String> multipartHeaders({bool includeAuth = true}) {
    return {
      if (includeAuth && UserSession.token.isNotEmpty)
        'Authorization': 'Bearer ${UserSession.token}',
    };
  }

  // Auth
  static const String login = '/login';
  static const String me    = '/users/me';
  static const String register = '/api/auth/register';
  static const String forgotPassword = '/password/forgot';
  static const String forgotPasswordVerifyOtp = '/password/verify-otp';
  static const String resetPassword = '/password/reset';
  static const String verifyOtp = '/users/verify-otp';
  static const String resendOtp = '/users/resend-otp';

  // Passenger
  static const String uploadImage = '/upload/';
  static const String passengerVerifyCnic = '/face-verification/verify-cnic';
  static const String passengerRegister = '/users/passenger';
  static const String passengerVerifyFace = '/face-verification/verify';

  // Driver
  static const String driverVerifyCnic = '/face-verification/verify-cnic';
  static const String driverRegister = '/users/driver';
  static const String driverEnable   = '/users/enable_driver';
  static const String driverFaceVerify = '/face-verification/verify';
  static const String driverVerifyLicense = '/license/verify';
  static const String driverRegisterVehicle = '/api/driver/register-vehicle';
  static const String driversRegister = '/drivers/register';
  static const String vehiclesList = '/vehicles/';
  static const String ridesActive = '/rides/active';

  // Rides
  static const String rides = '/api/rides';
  static const String ridesRecommend = '/ride_requests/search';
  static const String ridesOffer = '/rides/';
  static const String myRides   = '/rides/my';
  static const String bookRide = '/ride_requests/';
  static const String rideHistory = '/ride_requests/history';
  static const String rideRequests = '/rides/requests';
  static const String rideRequestAccept = '/ride_requests/{id}/accept';
  static const String rideRequestReject = '/ride_requests/{id}/reject';
  static const String rideLocation = '/location';
  static const String rideRate = '/ratings/';

  // Chat
  static const String chatMessages = '/chat';
  static const String chatSend     = '/chat/send';
}
class _AuthInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      final detail = err.response?.data['detail'];

      // Clear all session data
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); // clears token, name, role, everything

      final message = detail == 'session_expired'
          ? 'Session expired. Please log in again.'
          : 'Unauthorized. Please log in.';

      navigatorKey.currentState?.pushAndRemoveUntil(
  MaterialPageRoute(
    builder: (_) => HamrahLoginPage(sessionMessage: message),
  ),
  (route) => false,
);
    }
    super.onError(err, handler);
  }
}
