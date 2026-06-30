import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/UserSession.dart';
import '../config/api_config.dart';

class OsmLiveTrackingMap extends StatefulWidget {
  const OsmLiveTrackingMap({
    super.key,
    required this.pickupText,
    required this.destinationText,
    this.enableLiveLocation = false,
  });

  final String pickupText;
  final String destinationText;
  final bool enableLiveLocation;

  @override
  State<OsmLiveTrackingMap> createState() => _OsmLiveTrackingMapState();
}

class _OsmLiveTrackingMapState extends State<OsmLiveTrackingMap> {
  final MapController _mapController = MapController();
  final LatLng _fallbackCenter = const LatLng(24.8607, 67.0011); // Karachi

  LatLng? _pickupPoint;
  LatLng? _destinationPoint;
  Position? _currentPosition;

  StreamSubscription<Position>? _positionSubscription;
  WebSocketChannel? _wsChannel;

  List<LatLng> _roadRoutePoints = [];
  String _roadDistanceText = "Calculating route...";
  bool _hasMovedToInitialTarget = false;

  @override
  void initState() {
    super.initState();
    _loadLocationsAndRoute();

    if (widget.enableLiveLocation) {
      _startLiveLocation();
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }

  LatLng? _driverLivePoint;
  LatLng? _passengerLivePoint;

  void _connectWebSocket() {
    if (UserSession.activeRideId.isEmpty) return;
    final wsBase = ApiConfig.baseUrl.replaceFirst('http', 'ws');
    final url = '$wsBase/location/ws/${UserSession.activeRideId}?token=${UserSession.token}';
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(url));
      _wsChannel!.stream.listen((message) {
        try {
          final data = jsonDecode(message as String);
          if (data['type'] == 'status_update') {
            final status = data['status']?.toString();
            if (status == 'completed' || status == 'finished') {
              UserSession.activeRideId = '';
              UserSession.save();
            }
          } else if (data['type'] == 'driver_location') {
            final lat = double.tryParse(data['lat'].toString());
            final lng = double.tryParse(data['lng'].toString());
            if (lat != null && lng != null) {
              setState(() {
                _driverLivePoint = LatLng(lat, lng);
              });
            }
          } else if (data['type'] == 'passenger_location') {
            final lat = double.tryParse(data['lat'].toString());
            final lng = double.tryParse(data['lng'].toString());
            if (lat != null && lng != null) {
              setState(() {
                _passengerLivePoint = LatLng(lat, lng);
              });
            }
          }
        } catch (_) {}
      }, onError: (_) {
        _wsChannel = null;
      }, onDone: () {
        _wsChannel = null;
      });
    } catch (_) {}
  }

  void _sendLocationToBackend(Position position) {
    if (!widget.enableLiveLocation) return;
    if (UserSession.activeRideId.isEmpty) return;
    if (_wsChannel == null) _connectWebSocket();
    try {
      _wsChannel?.sink.add(jsonEncode({
        'type': 'location',
        'lat':  position.latitude,
        'lng':  position.longitude,
      }));
    } catch (_) {
      _wsChannel = null; // reconnect next time
    }
  }

  LatLng? _parseCoordinate(String input) {
    final parts = input.split(',');
    if (parts.length != 2) return null;

    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());

    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  Future<LatLng?> _getPointFromText(String input) async {
    final directPoint = _parseCoordinate(input);
    if (directPoint != null) return directPoint;

    final searchText = input.toLowerCase().contains("karachi")
        ? input
        : "$input, Karachi, Pakistan";

    final url = Uri.parse(
      "https://nominatim.openstreetmap.org/search"
          "?q=${Uri.encodeComponent(searchText)}"
          "&format=json"
          "&limit=1"
          "&countrycodes=pk",
    );

    try {
      final response = await http.get(
        url,
        headers: {
          "User-Agent": "finalyearproject-carpooling-app",
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;

        if (data.isNotEmpty) {
          final lat = double.tryParse(data[0]["lat"].toString());
          final lon = double.tryParse(data[0]["lon"].toString());

          if (lat != null && lon != null) {
            return LatLng(lat, lon);
          }
        }
      }
    } catch (e) {
      debugPrint("Geocoding error: $e");
    }

    return null;
  }

  Future<void> _loadLocationsAndRoute() async {
    setState(() {
      _roadDistanceText = "Calculating route...";
    });

    _pickupPoint = await _getPointFromText(widget.pickupText);
    _destinationPoint = await _getPointFromText(widget.destinationText);

    if (!mounted) return;

    setState(() {});

    if (_pickupPoint == null || _destinationPoint == null) {
      setState(() {
        _roadDistanceText = widget.pickupText.isEmpty || widget.destinationText.isEmpty
            ? "0 meters"
            : "Location not found";
      });
      _moveMapToBestLocation();
      return;
    }

    await _fetchRoadRoute();
    _moveMapToBestLocation();
  }

  Future<void> _fetchRoadRoute() async {
    if (_pickupPoint == null || _destinationPoint == null) return;

    final url = Uri.parse(
      "https://router.project-osrm.org/route/v1/driving/"
          "${_pickupPoint!.longitude},${_pickupPoint!.latitude};"
          "${_destinationPoint!.longitude},${_destinationPoint!.latitude}"
          "?overview=full&geometries=geojson",
    );

    try {
      final response = await http.get(url);

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          _roadDistanceText = "Route not available";
        });
        return;
      }

      final data = jsonDecode(response.body);

      if (data["routes"] == null || data["routes"].isEmpty) {
        setState(() {
          _roadDistanceText = "Route not available";
        });
        return;
      }

      final route = data["routes"][0];
      final num distanceMeters = route["distance"];
      final coordinates = route["geometry"]["coordinates"] as List;

      final points = coordinates.map<LatLng>((coord) {
        return LatLng(
          (coord[1] as num).toDouble(),
          (coord[0] as num).toDouble(),
        );
      }).toList();

      setState(() {
        _roadRoutePoints = points;

        if (distanceMeters < 1000) {
          _roadDistanceText = "${distanceMeters.toStringAsFixed(0)} meters";
        } else {
          _roadDistanceText =
          "${(distanceMeters / 1000).toStringAsFixed(2)} km";
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _roadDistanceText = "Route not available";
      });
    }
  }

  Future<void> _startLiveLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final current = await Geolocator.getCurrentPosition();

    if (!mounted) return;

    setState(() {
      _currentPosition = current;
    });

    _moveMapToBestLocation();

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 8,
      ),
    ).listen((position) {
      if (!mounted) return;

      setState(() {
        _currentPosition = position;
      });

      _moveMapToBestLocation();

      // Send to backend via WebSocket (both driver and passenger)
      if (widget.enableLiveLocation) {
        _sendLocationToBackend(position);
      }
    });
  }

  void _moveMapToBestLocation() {
    final livePoint = _currentPosition == null
        ? null
        : LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    if (!_hasMovedToInitialTarget) {
      if (_pickupPoint != null && _destinationPoint != null) {
        final center = LatLng(
          (_pickupPoint!.latitude + _destinationPoint!.latitude) / 2,
          (_pickupPoint!.longitude + _destinationPoint!.longitude) / 2,
        );

        _mapController.move(center, 13);
      } else {
        final target =
            livePoint ?? _pickupPoint ?? _destinationPoint ?? _fallbackCenter;

        _mapController.move(target, 13);
      }

      _hasMovedToInitialTarget = true;
      return;
    }

    if (widget.enableLiveLocation && livePoint != null) {
      _mapController.move(livePoint, 15);
    }
  }

  Marker _buildMarker({
    required LatLng point,
    required IconData icon,
    required Color color,
  }) {
    return Marker(
      point: point,
      width: 40,
      height: 40,
      child: Icon(icon, color: color, size: 34),
    );
  }

  @override
  Widget build(BuildContext context) {
    final livePoint = _currentPosition == null
        ? null
        : LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    final markers = <Marker>[
      if (_pickupPoint != null)
        _buildMarker(
          point: _pickupPoint!,
          icon: Icons.trip_origin,
          color: Colors.green,
        ),
      if (_destinationPoint != null)
        _buildMarker(
          point: _destinationPoint!,
          icon: Icons.location_on,
          color: Colors.red,
        ),
      if (widget.enableLiveLocation && livePoint != null)
        _buildMarker(
          point: livePoint,
          icon: Icons.navigation,
          color: Colors.blue,
        ),
      // Live location marker for the other party
      if (UserSession.isDriver && _passengerLivePoint != null)
        _buildMarker(
          point: _passengerLivePoint!,
          icon: Icons.person_pin_circle,
          color: Colors.purple,
        ),
      if (!UserSession.isDriver && _driverLivePoint != null)
        _buildMarker(
          point: _driverLivePoint!,
          icon: Icons.directions_car,
          color: Colors.orange,
        ),
    ];

    return Stack(
      children: [
        SafeArea(
          child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _pickupPoint ?? _destinationPoint ?? _fallbackCenter,
            initialZoom: 13,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
            // No built-in zoom buttons or other UI
          ),
          children: [
            TileLayer(
              urlTemplate:
              'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.example.finalyearproject',
              retinaMode: RetinaMode.isHighDensity(context),
            ),

            if (_roadRoutePoints.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _roadRoutePoints,
                    strokeWidth: 5,
                    color: Colors.teal,
                  ),
                ],
              ),

            MarkerLayer(markers: markers),
          ],
        ),
        ),

        Positioned(
          top: 14,
          left: 14,
          right: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 5),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.route, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Road Distance: $_roadDistanceText",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}