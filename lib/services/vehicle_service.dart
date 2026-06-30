import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'api_client.dart';

class VehicleService {
  static Future<List<Map<String, dynamic>>> fetchVehicles() async {
    final response = await http.get(
      ApiConfig.uri('/vehicles/'),
      headers: ApiConfig.jsonHeaders(),
    );
    ApiClient.ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return [];
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> addVehicle({
    required String vehicleNumber,
    required String modeOfTransport,
    String? model,
    String? colour,
  }) async {
    final response = await http.post(
      ApiConfig.uri('/vehicles/'),
      headers: ApiConfig.jsonHeaders(),
      body: jsonEncode({
        'vehicle_number': vehicleNumber,
        'mode_of_transport': modeOfTransport.toLowerCase(),
        if (model != null && model.isNotEmpty) 'vehicle_model': model,
        if (colour != null && colour.isNotEmpty) 'vehicle_colour': colour,
      }),
    );
    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    return data;
  }

  static Future<void> removeVehicle(int vehicleId) async {
    final response = await http.delete(
      ApiConfig.uri('/vehicles/$vehicleId'),
      headers: ApiConfig.jsonHeaders(),
    );
    ApiClient.ensureSuccess(response, ApiClient.decode(response));
  }
}
