import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'api_client.dart';
import 'UserSession.dart';

class LocationService {
  LocationService._();

  /// POST /location/{ride_id}/arrive — driver arrives at pickup
  static Future<void> arriveAtPickup(String rideId) async {
    try {
      final response = await http.post(
        ApiConfig.uri('/location/$rideId/arrive'),
        headers: ApiConfig.jsonHeaders(),
      );
      ApiClient.ensureSuccess(response, ApiClient.decode(response));
    } catch (_) {}
  }

  /// POST /location/{ride_id}/start — driver starts the ride
  static Future<void> startRide(String rideId) async {
    try {
      final response = await http.post(
        ApiConfig.uri('/location/$rideId/start'),
        headers: ApiConfig.jsonHeaders(),
      );
      ApiClient.ensureSuccess(response, ApiClient.decode(response));
    } catch (_) {}
  }

  /// Location update via WebSocket — handled in OsmLiveTrackingMap widget
  static Future<void> updateRideLocation({
    required String rideId,
    required double latitude,
    required double longitude,
    String role = 'driver',
  }) async {
    // Location is sent via WebSocket ws://{host}/location/ws/{ride_id}?token=...
    // This REST fallback is kept for compatibility but does nothing
  }

  /// GET ride location (fallback REST)
  static Future<Map<String, dynamic>> getRideLocation(String rideId) async {
    try {
      final response = await http.get(
        ApiConfig.uri('/location/$rideId/status'),
        headers: ApiConfig.jsonHeaders(),
      );
      if (response.statusCode == 200) {
        return ApiClient.decode(response);
      }
    } catch (_) {}
    return {};
  }
}
