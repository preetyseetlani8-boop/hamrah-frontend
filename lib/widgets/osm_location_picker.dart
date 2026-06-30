import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class OsmLocationPicker extends StatefulWidget {
  const OsmLocationPicker({
    super.key,
    required this.pickup,
    required this.destination,
    required this.onPickupChanged,
    required this.onDestinationChanged,
  });

  final LatLng? pickup;
  final LatLng? destination;
  final ValueChanged<LatLng> onPickupChanged;
  final ValueChanged<LatLng> onDestinationChanged;

  @override
  State<OsmLocationPicker> createState() => _OsmLocationPickerState();
}

class _OsmLocationPickerState extends State<OsmLocationPicker> {
  final MapController _mapController = MapController();
  LatLng _center = const LatLng(24.8607, 67.0011); // Karachi
  bool _selectingPickup = true;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _startLiveLocation();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
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
      _center = LatLng(current.latitude, current.longitude);
    });
    _mapController.move(_center, 14);

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).listen((position) {
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      if (_currentPosition != null)
        Marker(
          point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          width: 24,
          height: 24,
          child: const Icon(Icons.my_location, color: Colors.blue, size: 20),
        ),
      if (widget.pickup != null)
        Marker(
          point: widget.pickup!,
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, color: Color(0xFF00897B), size: 34),
        ),
      if (widget.destination != null)
        Marker(
          point: widget.destination!,
          width: 40,
          height: 40,
          child: const Icon(Icons.location_pin, color: Colors.redAccent, size: 34),
        ),
    ];

    return Stack(
      children: [
        SafeArea(
          child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 12,
            onTap: (_, point) {
              if (_selectingPickup) {
                widget.onPickupChanged(point);
                if (widget.destination == null) {
                  setState(() => _selectingPickup = false);
                }
              } else {
                widget.onDestinationChanged(point);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.example.finalyearproject',
            ),
            MarkerLayer(markers: markers),
          ],
        ),
        ),
      ],
    );
  }
}
