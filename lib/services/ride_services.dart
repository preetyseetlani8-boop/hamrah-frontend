import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'api_client.dart';
import 'UserSession.dart';
import '../utils/time_utils.dart';

extension StringExtension on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

class RideService {
  /// GET /api/rides/recommend — AI / matching drivers for passenger search.
  static Future<List<Map<String, dynamic>>> searchDrivers({
    required String pickup,
    required String destination,
    String? vehicleType,
    int? seats,
    String? gender,
    double? pickupLat,
    double? pickupLng,
    double? destLat,
    double? destLng,
    bool? isAC,
    DateTime? targetTime,
  }) async {
    final query = <String, String>{
      if (pickupLat != null)  'from_lat': pickupLat.toString(),
      if (pickupLng != null)  'from_lng': pickupLng.toString(),
      if (destLat != null)    'to_lat': destLat.toString(),
      if (destLng != null)    'to_lng': destLng.toString(),
      'target_time': (targetTime ?? DateTime.now()).toIso8601String(),
      if (vehicleType != null && vehicleType.isNotEmpty)
        'mode_of_transport': vehicleType.toLowerCase(),
      if (isAC != null) 'ac': isAC.toString(),
      if (gender != null && gender.isNotEmpty && gender != 'Any')
        'gender': gender.toLowerCase(),
    };

    final response = await http.get(
      ApiConfig.uri(ApiConfig.ridesRecommend, query: query),
      headers: ApiConfig.jsonHeaders(),
    );

    // Backend returns a list directly
    final body = jsonDecode(response.body);
    ApiClient.ensureSuccess(response);

    final raw = body is List ? body : (body['data'] ?? body['rides'] ?? []);
    if (raw is! List) return [];

    return raw
        .map((item) => _mapDriverForUi(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  static Map<String, dynamic> _mapDriverForUi(Map<String, dynamic> map) {
    return {
      'id':        map['id'],
      'ride_id':   map['id'],
      'driver_id': map['driver_id'],
      'name':      map['driver_name'] ?? map['name'] ?? 'Driver',
      'phone':     map['driver_phone'] ?? map['phone'] ?? '',
      'rating':    (map['driver_rating'] ?? map['rating'] ?? 0.0).toString(),
      'trips':     map['total_rides'] ?? map['total_trips'] ?? map['trips'] ?? 0,
      'vehicle':   map['mode_of_transport'] ?? map['vehicle'] ?? 'Car',
      'plate':     map['vehicle_number'] ?? map['plate'] ?? '',
      'gender':    map['gender_filter'] ?? map['gender'] ?? 'any',
      'seats':     map['seats_available'] ?? map['seats'] ?? 1,
      'price':     map['fare_per_seat'] != null
                     ? 'Rs. ${map['fare_per_seat']}'
                     : (map['price'] ?? map['fare'] ?? 'Rs. 0'),
      'eta':       _formatTime(map['departure_time']?.toString() ?? map['eta']?.toString() ?? ''),
      'from':      map['from_address'] ?? map['from'] ?? '',
      'to':        map['to_address'] ?? map['to'] ?? '',
      'ac':           map['ac'] ?? false,
      'status':       map['status'] ?? 'active',
      'pickup_points': map['pickup_points'] ?? [],
    };
  }

  /// GET /api/rides
  static Future<List<Map<String, dynamic>>> fetchRides({
    String? from,
    String? to,
    String? gender,
    int? seats,
  }) async {
    final query = <String, String>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (gender != null && gender.isNotEmpty) 'gender': gender,
      if (seats != null) 'seats': seats.toString(),
    };

    final response = await http.get(
      query.isEmpty
          ? ApiConfig.uri(ApiConfig.rides)
          : ApiConfig.uri(ApiConfig.rides, query: query),
      headers: ApiConfig.jsonHeaders(),
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);

    final raw = data['rides'] ?? data['data'] ?? [];
    if (raw is! List) return [];

    return raw.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  /// POST /ride_requests/ — passenger books a ride
  static Future<Map<String, dynamic>> bookRide({
    required String rideId,
    required int seatsBooked,
    String? pickup,
    String? destination,
  }) async {
    final response = await http.post(
      ApiConfig.uri(ApiConfig.bookRide),
      headers: ApiConfig.jsonHeaders(),
      body: jsonEncode({
        'ride_id': int.tryParse(rideId.toString()) ?? rideId,
      }),
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    return data;
  }

  /// POST /api/rides/offer — driver posts a ride.
  static Future<Map<String, dynamic>> offerRide({
    required int vehicleId,
    required String fromAddress,
    required String toAddress,
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    required double fare,
    required int seats,
    required bool ac,
    required String genderFilter,
    required DateTime departureTime,
    List<Map<String, dynamic>> extraPickups = const [],
    String modeOfTransport = 'car',
  }) async {
    final isBike = modeOfTransport.toLowerCase() == 'bike';
    final response = await http.post(
      ApiConfig.uri(ApiConfig.ridesOffer),
      headers: ApiConfig.jsonHeaders(),
      body: jsonEncode({
        'vehicle_id':     vehicleId,
        'from_address':   fromAddress,
        'from_lat':       fromLat,
        'from_lng':       fromLng,
        'to_address':     toAddress,
        'to_lat':         toLat,
        'to_lng':         toLng,
        'departure_time': departureTime.toUtc().toIso8601String(),
        'gender_filter':  genderFilter.toLowerCase(),
        'fare_per_seat':  fare,
        if (!isBike) 'seats_available': seats,
        if (!isBike) 'ac': ac,
        if (extraPickups.isNotEmpty) 'pickup_points': extraPickups,
      }),
    );

    final data = ApiClient.decode(response);
    ApiClient.ensureSuccess(response, data);
    return data;
  }

  /// GET /ride_requests/history — passenger ride history
  static Future<List<Map<String, dynamic>>> fetchRideHistory() async {
    final response = await http.get(
      ApiConfig.uri(ApiConfig.rideHistory),
      headers: ApiConfig.jsonHeaders(),
    );
    ApiClient.ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return [];

    return decoded.map((r) {
      final map = Map<String, dynamic>.from(r);
      // Parse departure_time
      String date = '', time = '';
      try {
      date = TimeUtils.formatHistoryDate(map['departure_time']?.toString());
      time = TimeUtils.formatTwentyFourHour(map['departure_time']?.toString());
      } catch (_) {}

      final statusRaw = map['status']?.toString() ?? 'pending';
      final statusLabel = statusRaw == 'completed' ? 'Completed'
          : statusRaw == 'accepted' ? 'Accepted'
          : statusRaw == 'picked_up' ? 'In Progress'
          : statusRaw == 'cancelled_by_passenger' || statusRaw == 'cancelled_by_driver'
          ? 'Cancelled'
          : statusRaw == 'pending' ? 'Pending'
          : statusRaw.capitalize();

      return {
        'driver':      map['driver_name'] ?? 'Driver',
        'vehicle':     map['vehicle_model'] ?? map['vehicle_number'] ?? '',
        'pickup':      map['from_address'] ?? '',
        'destination': map['to_address'] ?? '',
        'date':        date,
        'time':        time,
        'fare':        map['fare'] ?? 0,    // pass raw number for safer math
        'fare_display':'Rs. ${map['fare'] ?? 0}',
        'rating':      0,
        'status':      statusLabel,
        'raw_status':  statusRaw,           // for total calculation
      };
    }).toList();
  }

  static String _formatTime(String raw) {
    return TimeUtils.formatTime(raw);
  }

  /// GET /rides/active — driver's active/ongoing rides
  static Future<List<Map<String, dynamic>>> fetchActiveRides() async {
    final response = await http.get(
      ApiConfig.uri(ApiConfig.ridesActive),
      headers: ApiConfig.jsonHeaders(),
    );
    ApiClient.ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  /// GET /rides/my — driver's posted rides
  static Future<List<Map<String, dynamic>>> fetchMyRides() async {
    final response = await http.get(
      ApiConfig.uri(ApiConfig.myRides),
      headers: ApiConfig.jsonHeaders(),
    );
    ApiClient.ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  /// GET /api/rides/requests — driver incoming requests.
  static Future<List<Map<String, dynamic>>> fetchDriverRequests() async {
    final response = await http.get(
      ApiConfig.uri(ApiConfig.rideRequests),
      headers: ApiConfig.jsonHeaders(),
    );

    ApiClient.ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    final raw = decoded is List ? decoded : (decoded['requests'] ?? decoded['data'] ?? []);
    if (raw is! List) return [];

    return raw
        .map((r) => mapDriverRequestForUi(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  static Map<String, dynamic> mapDriverRequestForUi(Map<String, dynamic> map) {
    return {
      'id':              map['id']?.toString() ?? '',
      'ride_id':         map['ride_id']?.toString() ?? map['rideId']?.toString() ?? '',
      'passenger_name':  map['passenger_name'] ?? map['passengerName'] ?? 'Passenger',
      'passengerName':   map['passenger_name'] ?? map['passengerName'] ?? 'Passenger',
      'from_address':    map['from_address'] ?? map['pickup'] ?? '',
      'to_address':      map['to_address'] ?? map['destination'] ?? '',
      'pickup':          map['from_address'] ?? map['pickup'] ?? '',
      'destination':     map['to_address'] ?? map['destination'] ?? '',
      'fare':            map['fare'] ?? map['fare_per_seat'] ?? 0,
      'seats':           map['seats'] ?? 1,
      'gender':          map['gender'] ?? '',
      'status':          map['status'] ?? 'pending',
      'distance_from_route': map['distance_from_route'] ?? 0,
      if (map['departure_time'] != null) 'departure_time': map['departure_time'],
    };
  }

  /// POST /rides/{ride_id}/cancel
  static Future<void> cancelRide(String rideId) async {
    final response = await http.post(
      ApiConfig.uri('/rides/$rideId/cancel'),
      headers: ApiConfig.jsonHeaders(),
    );
    ApiClient.ensureSuccess(response, ApiClient.decode(response));
  }

  /// PATCH /rides/{ride_id}
  static Future<void> editRide(String rideId, Map<String, dynamic> updates) async {
    final response = await http.patch(
      ApiConfig.uri('/rides/$rideId'),
      headers: ApiConfig.jsonHeaders(),
      body: jsonEncode(updates),
    );
    ApiClient.ensureSuccess(response, ApiClient.decode(response));
  }

  /// POST /rides/requests/{request_id}/pickup
  static Future<void> pickupPassenger(String requestId) async {
    final response = await http.post(
      ApiConfig.uri('/rides/requests/$requestId/pickup'),
      headers: ApiConfig.jsonHeaders(),
    );
    ApiClient.ensureSuccess(response, ApiClient.decode(response));
  }

  /// POST /rides/{ride_id}/complete
  static Future<void> completeRide(String rideId) async {
    final response = await http.post(
      ApiConfig.uri('/rides/$rideId/complete'),
      headers: ApiConfig.jsonHeaders(),
    );
    ApiClient.ensureSuccess(response, ApiClient.decode(response));
  }

  static Future<void> acceptRequest(String requestId) async {
    final response = await http.post(
      ApiConfig.uri('/ride_requests/$requestId/accept'),
      headers: ApiConfig.jsonHeaders(),
    );
    ApiClient.ensureSuccess(response, ApiClient.decode(response));
  }

  static Future<void> rejectRequest(String requestId) async {
    final response = await http.post(
      ApiConfig.uri('/ride_requests/$requestId/reject'),
      headers: ApiConfig.jsonHeaders(),
    );
    ApiClient.ensureSuccess(response, ApiClient.decode(response));
  }

  /// POST /api/rides/rate
  static Future<void> rateRide({
    required String rideId,
    required int stars,
    String? comment,
    List<String>? tags,
  }) async {
    final response = await http.post(
      ApiConfig.uri('/ratings/'),
      headers: ApiConfig.jsonHeaders(),
      body: jsonEncode({
        'ride_id': int.tryParse(rideId) ?? 0,
        'stars':   stars,
        if (comment != null && comment.isNotEmpty) 'review': comment,
        if (tags != null && tags.isNotEmpty) 'tags': tags,
      }),
    );
    ApiClient.ensureSuccess(response, ApiClient.decode(response));
  }

  /// POST /ratings/passenger
  static Future<void> ratePassenger({
    required String rideId,
    required String passengerId,
    required int stars,
    String? comment,
    List<String>? tags,
  }) async {
    final response = await http.post(
      ApiConfig.uri('/ratings/passenger'),
      headers: ApiConfig.jsonHeaders(),
      body: jsonEncode({
        'ride_id': int.tryParse(rideId) ?? 0,
        'passenger_id': int.tryParse(passengerId) ?? 0,
        'stars': stars,
        if (comment != null && comment.isNotEmpty) 'review': comment,
        if (tags != null && tags.isNotEmpty) 'tags': tags,
      }),
    );
    ApiClient.ensureSuccess(response, ApiClient.decode(response));
  }

  /// POST /ride_requests/{request_id}/cancel
  static Future<void> cancelRequest(String requestId) async {
    final response = await http.post(
      ApiConfig.uri('/ride_requests/$requestId/cancel'),
      headers: ApiConfig.jsonHeaders(),
    );
    ApiClient.ensureSuccess(response, ApiClient.decode(response));
  }
}
