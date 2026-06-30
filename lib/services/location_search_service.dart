
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class LocationSuggestion {
  final String displayName;
  final String description;
  final LatLng coordinates;

  LocationSuggestion({
    required this.displayName,
    required this.description,
    required this.coordinates,
  });

  factory LocationSuggestion.fromJson(Map<String, dynamic> json) {
    return LocationSuggestion(
      displayName: json['display_name'] ?? '',
      description: _formatDescription(json),
      coordinates: LatLng(
        double.tryParse(json['lat']?.toString() ?? '') ?? 0,
        double.tryParse(json['lon']?.toString() ?? '') ?? 0,
      ),
    );
  }

  static String _formatDescription(Map<String, dynamic> json) {
    final address = json['address'] as Map<String, dynamic>?;
    if (address == null) return json['display_name'] ?? '';

    final parts = <String>[];

    // Specific place name (shop, building, amenity)
    final placeName = address['amenity'] ??
        address['shop'] ??
        address['building'] ??
        address['tourism'] ??
        address['leisure'];
    if (placeName != null) parts.add(placeName.toString());

    // Street / road
    if (address['road'] != null) parts.add(address['road'].toString());

    // Neighbourhood / suburb (most important for Karachi — DHA, Gulshan, Clifton etc.)
    final area = address['neighbourhood'] ??
        address['suburb'] ??
        address['quarter'] ??
        address['residential'];
    if (area != null) parts.add(area.toString());

    // District / city district
    final district = address['city_district'] ?? address['district'];
    if (district != null) parts.add(district.toString());

    // City
    final city = address['city'] ?? address['town'] ?? address['village'];
    if (city != null) parts.add(city.toString());

    return parts.isNotEmpty ? parts.join(', ') : json['display_name'] ?? '';
  }
}

class LocationSearchService {
  static const String _nominatimUrl = 'https://nominatim.openstreetmap.org';
  static const String _photonUrl    = 'https://photon.komoot.io';

  static Timer? _debounce;

  // Main search — tries Photon first (better Karachi results),
  // falls back to Nominatim if Photon returns nothing.
  static Future<List<LocationSuggestion>> searchLocations(String query) async {
    if (query.isEmpty || query.length < 2) return [];

    // Debounce: cancel previous call if user is still typing
    _debounce?.cancel();
    final completer = Completer<List<LocationSuggestion>>();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final results = await _fetchFromPhoton(query);
      if (results.isNotEmpty) {
        completer.complete(results);
      } else {
        completer.complete(await _fetchFromNominatim(query));
      }
    });
    return completer.future;
  }

  // ── Photon (OpenStreetMap-based, excellent Pakistan coverage) ──────────────
  static Future<List<LocationSuggestion>> _fetchFromPhoton(String query) async {
    try {
      // lat/lon bias = centre of Karachi
      final uri = Uri.parse(
        '$_photonUrl/api'
            '?q=${Uri.encodeComponent(query)}'
            '&limit=10'
            '&lang=en'
            '&lat=24.8607'
            '&lon=67.0011',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'HamrahApp/1.0',
      }).timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? [];

      return features
          .map((f) => _photonFeatureToSuggestion(f as Map<String, dynamic>))
          .whereType<LocationSuggestion>()
          .toList();
    } catch (e) {
      return [];
    }
  }

  static LocationSuggestion? _photonFeatureToSuggestion(
      Map<String, dynamic> feature) {
    try {
      final props = feature['properties'] as Map<String, dynamic>? ?? {};
      final coords = (feature['geometry']?['coordinates'] as List?)
          ?.map((e) => double.tryParse(e.toString()) ?? 0.0)
          .toList();
      if (coords == null || coords.length < 2) return null;

      final parts = <String>[];
      for (final key in ['name', 'street', 'district', 'suburb',
        'neighbourhood', 'city', 'county']) {
        final v = props[key]?.toString();
        if (v != null && v.isNotEmpty && !parts.contains(v)) parts.add(v);
      }

      final description = parts.join(', ');
      if (description.isEmpty) return null;

      return LocationSuggestion(
        displayName: description,
        description: description,
        coordinates: LatLng(coords[1], coords[0]), // GeoJSON is [lon, lat]
      );
    } catch (_) {
      return null;
    }
  }

  // ── Nominatim fallback ─────────────────────────────────────────────────────
  static Future<List<LocationSuggestion>> _fetchFromNominatim(
      String query) async {
    try {
      final uri = Uri.parse(
        '$_nominatimUrl/search'
            '?format=json'
            '&q=${Uri.encodeComponent(query)}'
            '&limit=8'
            '&addressdetails=1'
            '&countrycodes=pk'
            '&viewbox=66.5,23.5,67.6,25.2'
            '&bounded=0'
            '&accept-language=en',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'HamrahApp/1.0',
      }).timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as List<dynamic>;
      return data
          .map((j) => LocationSuggestion.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Reverse geocode (tap on map → address) ─────────────────────────────────
  static Future<String?> reverseGeocode(LatLng coordinates) async {
    try {
      final uri = Uri.parse(
        '$_nominatimUrl/reverse'
            '?format=json'
            '&lat=${coordinates.latitude}'
            '&lon=${coordinates.longitude}'
            '&addressdetails=1'
            '&accept-language=en',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'HamrahApp/1.0',
      }).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['display_name'] as String?;
      }
    } catch (_) {}
    return null;
  }
}
