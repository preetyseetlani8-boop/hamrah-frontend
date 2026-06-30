import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'api_client.dart';
import 'UserSession.dart';

/// Holds registration data between screens.
class RegistrationService {
  RegistrationService._();

  static String password        = '';
  static String firstName       = '';
  static String lastName        = '';
  static String cnicNumber      = '';
  static String studentId       = '';
  static String phone           = '';
  static String email           = '';
  static String gender          = 'Male';
  static String cnicImageUrl    = '';
  static String liveImageUrl    = '';
  static String licenseImageUrl = '';
  // vehicle info saved from CarDetailsPage
  static String vehicleNumber    = '';
  static String vehicleTransport = '';
  static String vehicleModel     = '';
  static String vehicleColour    = '';
  static bool   faceVerified     = false;
  static final List<Map<String, dynamic>> vehicleDrafts = [];

  static void clearDraft() {
    password        = '';
    firstName       = '';
    lastName        = '';
    cnicNumber      = '';
    studentId       = '';
    phone           = '';
    email           = '';
    gender          = 'Male';
    cnicImageUrl    = '';
    liveImageUrl    = '';
    licenseImageUrl = '';
    vehicleNumber    = '';
    vehicleTransport = '';
    vehicleModel     = '';
    vehicleColour    = '';
    faceVerified    = false;
    vehicleDrafts.clear();
  }

  // ─────────────────────────────────────────────
  // Upload any image file → get URL back
  // POST /upload  |  field: image
  // ─────────────────────────────────────────────
  static Future<String> uploadImage(File imageFile) async {
    final request = http.MultipartRequest(
      'POST', ApiConfig.uri(ApiConfig.uploadImage))
      ..files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

    request.headers.addAll(ApiConfig.multipartHeaders(includeAuth: false));

    final data = await ApiClient.sendMultipart(request);
    final url = data['url']?.toString() ?? '';
    if (url.isEmpty) throw Exception('Upload failed: no URL returned.');
    return url;
  }

  // ─────────────────────────────────────────────
  // Face comparison — send both URLs
  // POST /face-verification/verify
  // ─────────────────────────────────────────────
  static Future<Map<String, dynamic>> verifyFaceWithUrls({
    required String cnicUrl,
    required String liveUrl,
  }) async {
    final response = await http.post(
      ApiConfig.uri(ApiConfig.driverFaceVerify),
      headers: ApiConfig.jsonHeaders(includeAuth: false),
      body: jsonEncode({
        'cnic_image_url': cnicUrl,
        'live_image_url': liveUrl,
      }),
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    faceVerified = data['verified'] == true;
    return data;
  }

  // ─────────────────────────────────────────────
  // License OCR verification
  // POST /license/verify
  // ─────────────────────────────────────────────
  static Future<Map<String, dynamic>> verifyLicense({
    required String licenseUrl,
  }) async {
    final response = await http.post(
      ApiConfig.uri(ApiConfig.driverVerifyLicense),
      headers: ApiConfig.jsonHeaders(includeAuth: false),
      body: jsonEncode({
        'license_image_url': licenseUrl,
        if (cnicNumber.isNotEmpty) 'cnic_number': cnicNumber,
      }),
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    return data;
  }

  // ─────────────────────────────────────────────
  // Passenger registration
  // POST /users/passenger
  // ─────────────────────────────────────────────
  static Future<Map<String, dynamic>> registerPassenger({
    required String firstName,
    required String lastName,
    required String studentId,
    required String phone,
    required String email,
    required String cnicNumber,
    required String gender,
  }) async {
    final response = await http.post(
      ApiConfig.uri(ApiConfig.passengerRegister),
      headers: ApiConfig.jsonHeaders(includeAuth: false),
      body: jsonEncode({
        'first_name': firstName,
        'last_name':  lastName,
        'dsu_reg_id': studentId,
        'phone_number': phone,
        'email':      email,
        'gender':     gender.toLowerCase(),
        'password':   password,
      }),
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);

    if (data['token'] != null) {
      UserSession.token = data['token'].toString();
    }
    return data;
  }

  // ─────────────────────────────────────────────
  // Driver registration
  // POST /users/driver
  // ─────────────────────────────────────────────
  static Future<Map<String, dynamic>> registerDriver() async {
    final vehicles = vehicleDrafts.isNotEmpty
        ? vehicleDrafts
        : [
            {
              'vehicle_number': vehicleNumber,
              'mode_of_transport': vehicleTransport.toLowerCase(),
              if (vehicleModel.isNotEmpty) 'vehicle_model': vehicleModel,
              if (vehicleColour.isNotEmpty) 'vehicle_colour': vehicleColour,
            }
          ];

    // First try: new driver registration
    final response = await http.post(
      ApiConfig.uri(ApiConfig.driverRegister),
      headers: ApiConfig.jsonHeaders(includeAuth: false),
      body: jsonEncode({
        'first_name':        firstName,
        'last_name':         lastName,
        'dsu_reg_id':        studentId,
        'phone_number':      phone,
        'email':             email,
        'gender':            gender.toLowerCase(),
        'password':          password,
        'cnic_number':       cnicNumber,
        'cnic_image_url':    cnicImageUrl,
        'live_image_url':    liveImageUrl,
        'license_image_url': licenseImageUrl,
        'vehicles':          vehicles,
      }),
    );

    final data = ApiClient.decode(response);

    // Already passenger with same DSU ID → add driver role
    if (response.statusCode == 400) {
      final msg = data['detail']?.toString() ?? '';
      if (msg.contains('already registered') || msg.contains('already exists')) {
        return await _enableDriver(vehicles);
      }
    }

    ApiClient.ensureSuccess(response, data);
    if (data['token'] != null) UserSession.token = data['token'].toString();
    return data;
  }

  static Future<Map<String, dynamic>> _enableDriver(
      List<Map<String, dynamic>> vehicles) async {
    final response = await http.post(
      ApiConfig.uri(ApiConfig.driverEnable),
      headers: ApiConfig.jsonHeaders(includeAuth: false),
      body: jsonEncode({
        'dsu_reg_id':        studentId,
        'email':             email,
        'cnic_image_url':    cnicImageUrl,
        'live_image_url':    liveImageUrl,
        'license_image_url': licenseImageUrl,
        'vehicles':          vehicles,
      }),
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    if (data['token'] != null) UserSession.token = data['token'].toString();
    // Use existing account's email for OTP verification
    if (data['email'] != null) UserSession.email = data['email'].toString();
    return data;
  }

  /// POST /drivers/register — logged-in passenger becomes driver
  static Future<Map<String, dynamic>> registerDriverUpgrade() async {
    final vehicles = vehicleDrafts.isNotEmpty
        ? vehicleDrafts
        : [
            {
              'vehicle_number': vehicleNumber,
              'mode_of_transport': vehicleTransport.toLowerCase(),
              if (vehicleModel.isNotEmpty) 'vehicle_model': vehicleModel,
              if (vehicleColour.isNotEmpty) 'vehicle_colour': vehicleColour,
            }
          ];

    final response = await http.post(
      ApiConfig.uri(ApiConfig.driversRegister),
      headers: ApiConfig.jsonHeaders(),
      body: jsonEncode({
        'dsu_reg_id': studentId.isNotEmpty ? studentId : UserSession.studentId,
        'email': email.isNotEmpty ? email : UserSession.email,
        'cnic_image_url': cnicImageUrl,
        'live_image_url': liveImageUrl,
        'license_image_url': licenseImageUrl,
        'vehicles': vehicles,
      }),
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    if (data['email'] != null) UserSession.email = data['email'].toString();
    return data;
  }
}
