// lib/screens/Ridebook.dart
// ─────────────────────────────────────────────────────────────────────────────
// CHANGES FROM ORIGINAL:
//   1. Added imports: user_session.dart, ride_history_screen.dart,
//      passenger_profile_screen.dart
//   2. _buildDrawer() now reads name/studentId from UserSession instead of
//      hardcoded strings.
//   3. _buildDrawer() has three new ListTile entries: My Profile, Ride History,
//      Notifications (placeholder).
//   4. The italic tagline text was removed to make space for the new tiles.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:finalyearproject/screens/checkingscreen.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'package:latlong2/latlong.dart';
import '../widgets/top_right_alert.dart';
import '../widgets/osm_location_picker.dart';
import '../widgets/location_autocomplete.dart';
import '../services/UserSession.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'RideHistoryScreen.dart';             // ← NEW
import 'PassengerProfileScreen.dart';        // ← NEW
import 'Notifications.dart';            // ← NEW
import 'offerride.dart';
import 'regRiderDriver.dart';
import 'RideConfirmation.dart';
import 'RateDriver.dart';

class RideSearchScreen extends StatefulWidget {
  /// Optional prefill values (used when opening from an AI ride
  /// recommendation notification).
  final String? prefillRideId;
  final String? prefillFrom;
  final String? prefillTo;
  final double? prefillFromLat;
  final double? prefillFromLng;
  final double? prefillToLat;
  final double? prefillToLng;
  final DateTime? prefillDepartureTime;

  const RideSearchScreen({
    super.key,
    this.prefillRideId,
    this.prefillFrom,
    this.prefillTo,
    this.prefillFromLat,
    this.prefillFromLng,
    this.prefillToLat,
    this.prefillToLng,
    this.prefillDepartureTime,
  });

  @override
  State<RideSearchScreen> createState() => _RideSearchScreenState();
}

class _RideSearchScreenState extends State<RideSearchScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final TextEditingController pickupController = TextEditingController();
  final TextEditingController destinationController = TextEditingController();
  LatLng? _pickupPoint;
  LatLng? _destinationPoint;

  String selectedGender = 'Any';
  int selectedSeats = 1;
  String selectedMode = 'Car';
  bool isAC = false;
  DateTime selectedDateTime = DateTime.now().add(const Duration(minutes: 15));
  Map<String, dynamic>? _activeRide;
  Timer? _refreshTimer;
  String? _lastStatus;
  String? _lastRequestStatus;
  bool _initialLoadDone = false;
  bool _hasDriverRole = false;
  String? _recommendedRideId;

  @override
  void initState() {
    super.initState();

    _hasDriverRole = UserSession.registeredRoles.contains('driver');
    _refreshUserRoles();
    _loadActiveRide();
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadActiveRide();
    });
    // Apply prefill values if the screen was opened from a notification
    if (widget.prefillFrom != null) {
      pickupController.text = widget.prefillFrom!;
    }
    if (widget.prefillTo != null) {
      destinationController.text = widget.prefillTo!;
    }
    if (widget.prefillFromLat != null && widget.prefillFromLng != null) {
      _pickupPoint = LatLng(widget.prefillFromLat!, widget.prefillFromLng!);
    }
    if (widget.prefillToLat != null && widget.prefillToLng != null) {
      _destinationPoint = LatLng(widget.prefillToLat!, widget.prefillToLng!);
    }
    // Apply prefill departure time from recommendation
    if (widget.prefillDepartureTime != null) {
      selectedDateTime = widget.prefillDepartureTime!;
    }
    _recommendedRideId = widget.prefillRideId;
    
    // AUTO-EXECUTE SEARCH ONLY IF WE HAVE PRE-FILL VALUES
    // (means this screen was opened from notification tap)
    if (widget.prefillFrom != null && widget.prefillTo != null && 
        _pickupPoint != null && _destinationPoint != null) {
      // Wait a moment to let the UI settle then auto-search
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _requestRide();
      });
    }
  }

  Future<void> _refreshUserRoles() async {
    try {
      await AuthService.syncSessionFromMe();
      if (!mounted) return;
      setState(() {
        _hasDriverRole = UserSession.registeredRoles.contains('driver');
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadActiveRide() async {
    try {
      final response = await http.get(
        ApiConfig.uri('/ride_requests/active'),
        headers: ApiConfig.jsonHeaders(),
      );
      if (response.statusCode == 200) {
        if (response.body == 'null' || response.body.isEmpty) {
          // Ride ended — only if we had a real active status before
          if (_initialLoadDone && _lastStatus != null) {
            _refreshTimer?.cancel();
            if (mounted) {
              setState(() { _activeRide = null; _lastStatus = null; _lastRequestStatus = null; });
              TopRightAlert.show(context,
                  title: '✅ Ride Completed',
                  message: 'You have reached your destination!',
                  isError: false);
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted && UserSession.activeRideId.isNotEmpty) {
                  Navigator.push(context,
                    MaterialPageRoute(builder: (_) => RateDriverScreen(
                      driver: {'name': 'Driver', 'ride_id': int.tryParse(UserSession.activeRideId)},
                    )),
                  ).then((_) {
                    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
                      if (mounted) _loadActiveRide();
                    });
                  });
                }
              });
            }
          } else {
            if (mounted) setState(() => _activeRide = null);
          }
          return;
        }
        final data = jsonDecode(response.body);
        if (data != null && mounted) {
          final newStatus = data['status']?.toString();
          final reqStatus = data['request_status']?.toString();

          // Persist request ID for WS filtering
          final requestId = data['request_id']?.toString() ?? '';
          if (requestId.isNotEmpty) UserSession.activeRequestId = requestId;

          // Handle REQUEST STATUS changes first!
          if (_lastRequestStatus != reqStatus) {
            // Handle driver arrived (pickup status)
            if (reqStatus == 'pickup') {
              if (data['ride_id'] != null) {
                UserSession.activeRideId = data['ride_id'].toString();
              }
              TopRightAlert.show(context,
                  title: '📍 Driver Arrived!',
                  message: 'Your driver is at the pickup point.',
                  isError: false);
            }
            // Handle ride started (riding status)
            else if (reqStatus == 'riding') {
              TopRightAlert.show(context,
                  title: '🚗 Ride Started!',
                  message: 'Your ride has started!',
                  isError: false);
            }
            _lastRequestStatus = reqStatus;
          }

          // Always update UI state, even if status didn't change
          _lastStatus = newStatus;
          _initialLoadDone = true;
          setState(() => _activeRide = Map<String, dynamic>.from(data));
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          Positioned.fill(
            child: OsmLocationPicker(
              pickup: _pickupPoint,
              destination: _destinationPoint,
              onPickupChanged: (point) {
                setState(() {
                  _pickupPoint = point;
                  pickupController.text =
                      '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
                });
              },
              onDestinationChanged: (point) {
                setState(() {
                  _destinationPoint = point;
                  destinationController.text =
                      '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
                });
              },
            ),
          ),

          // MENU BUTTON
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Material(
                elevation: 4,
                shape: const CircleBorder(),
                color: Colors.white,
                child: IconButton(
                  icon: const Icon(Icons.menu_rounded, color: Color(0xFF00897B)),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
              ),
            ),
          ),

          // BOTTOM SHEET
          DraggableScrollableSheet(
            initialChildSize: 0.55,
            minChildSize: 0.45,
            maxChildSize: 0.92,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 50, height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Active Ride Banner — same look as LiveDriverScreen ──
                      if (_activeRide != null) ...[
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RideConfirmationScreen(
                                driver: {
                                  'name': _activeRide!['driver_name'] ?? 'Driver',
                                  'rating': '0',
                                  'trips': 0,
                                  'vehicle': 'Car',
                                  'plate': _activeRide!['vehicle_number'] ?? '',
                                  'price': 'Rs. ${_activeRide!['fare_per_seat'] ?? 0}',
                                  'eta': _activeRide!['departure_time'] ?? '--',
                                  'from': _activeRide!['from_address'] ?? '',
                                  'to': _activeRide!['to_address'] ?? '',
                                  'gender': 'any',
                                  'ac': false,
                                  'ride_id': _activeRide!['ride_id'],
                                },
                                pickup: _activeRide!['from_address'] ?? '',
                                destination: _activeRide!['to_address'] ?? '',
                                rideId: _activeRide!['ride_id']?.toString(),
                              ),
                            ),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00897B), Color(0xFF26A69A)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00897B).withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.directions_car,
                                              color: Colors.white, size: 22),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          () {
                                            final reqStatus = _activeRide!['request_status']?.toString() ?? '';
                                            final status = _activeRide!['status']?.toString() ?? '';
                                            if (_activeRide!['status_label'] != null) {
                                              return _activeRide!['status_label'];
                                            }
                                            if (reqStatus == 'pickup' || status == 'arrived') {
                                              return '📍 Driver Has Arrived!';
                                            } else if (reqStatus == 'riding' || status == 'ongoing') {
                                              return '🚗 Ride in progress';
                                            } else if (reqStatus == 'dropped' || status == 'completed') {
                                              return '✅ Completed';
                                            } else if (reqStatus == 'accepted' || status == 'accepted') {
                                              return '✅ Driver Accepted';
                                            } else {
                                              return '⏳ Waiting for driver';
                                            }
                                          }(),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15),
                                        ),
                                      ],
                                    ),
                                    GestureDetector(
                                      onTap: _loadActiveRide,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.refresh,
                                            color: Colors.white, size: 16),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Icon(Icons.my_location,
                                        color: Colors.white, size: 14),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _activeRide!['from_address']?.toString() ?? '',
                                        style: TextStyle(
                                            color: Colors.white.withOpacity(0.95),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on,
                                        color: Colors.white, size: 14),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _activeRide!['to_address']?.toString() ?? '',
                                        style: TextStyle(
                                            color: Colors.white.withOpacity(0.95),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_activeRide!['driver_name'] != null) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.person, color: Colors.white, size: 14),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            'Driver: ${_activeRide!['driver_name']}',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Tap to view live ride →',
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.85),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const Text('Trip details',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: Color(0xFF00897B))),
                      const SizedBox(height: 20),

                      // LOCATION INPUTS
                      Column(
                        children: [
                          LocationAutocomplete(
                            controller: pickupController,
                            label: 'Pickup Location',
                            hint: 'Search pickup location',
                            icon: Icons.my_location,
                            iconColor: const Color(0xFF00897B),
                            onLocationSelected: (coordinates, displayName) {
                              setState(() {
                                _pickupPoint = coordinates;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          LocationAutocomplete(
                            controller: destinationController,
                            label: 'Destination',
                            hint: 'Search destination',
                            icon: Icons.location_on,
                            iconColor: Colors.redAccent,
                            onLocationSelected: (coordinates, displayName) {
                              setState(() {
                                _destinationPoint = coordinates;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      _modeSelector(),
                      const SizedBox(height: 12),

                      if (selectedMode == 'Car') ...[
                        _acToggle(),
                        const SizedBox(height: 12),
                      ],

                      Row(
                        children: [
                          Expanded(child: _genderDropdown()),
                          const SizedBox(width: 12),
                          Expanded(child: _seatsStepper()),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Date & Time Picker
                      GestureDetector(
                        onTap: _pickDateTime,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F4F7),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time, size: 18, color: Color(0xFF00897B)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  () {
                                    final h = selectedDateTime.hour % 12 == 0 ? 12 : selectedDateTime.hour % 12;
                                    final m = selectedDateTime.minute.toString().padLeft(2,'0');
                                    final p = selectedDateTime.hour >= 12 ? 'PM' : 'AM';
                                    return '${selectedDateTime.day}/${selectedDateTime.month}/${selectedDateTime.year}  $h:$m $p';
                                  }(),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF212121)),
                                ),
                              ),
                              const Icon(Icons.edit_calendar_outlined, size: 16, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _requestRide,
                          icon: const Icon(Icons.hail, size: 20),
                          label: const Text('Search rides',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00897B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 17),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
// xhnages neeed
  Future<void> _pickDateTime() async {
  final date = await showDatePicker(
    context: context,
    initialDate: selectedDateTime,
    firstDate: DateTime.now(),
    lastDate: DateTime.now().add(const Duration(days: 30)),
  );

  if (date == null) return;
  if (!mounted) return;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(selectedDateTime),
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          alwaysUse24HourFormat: false,
        ),
        child: child!,
      );
    },
  );

  if (time == null) return;

  final selected = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );

  if (selected.isBefore(DateTime.now())) {
    if (!mounted) return;

    TopRightAlert.show(
      context,
      title: 'Invalid Time',
      message: 'Please select a future time.',
      isError: true,
    );
    return;
  }

  setState(() => selectedDateTime = selected);
}
// need
  void _requestRide() {
    if (pickupController.text.isEmpty || destinationController.text.isEmpty) {
      TopRightAlert.show(
        context,
        title: 'Location Required',
        message: 'Enter pickup and destination.',
        isError: true,
      );
      return;
    }
    
    if (_pickupPoint == null || _destinationPoint == null) {
      TopRightAlert.show(
        context,
        title: 'Invalid Location',
        message: 'Select locations from suggestions.',
        isError: true,
      );
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckingCarsScreen(
          pickup: pickupController.text,
          destination: destinationController.text,
          vehicleType: selectedMode,
          seats: selectedSeats,
          gender: selectedGender,
          pickupLat: _pickupPoint?.latitude,
          pickupLng: _pickupPoint?.longitude,
          destLat: _destinationPoint?.latitude,
          destLng: _destinationPoint?.longitude,
          isAC: isAC,
          targetTime: selectedDateTime,
        ),
      ),
    );
  }

  Widget _modeSelector() {
    return Row(
      children: ['Car', 'Bike'].map((mode) {
        final isSelected = selectedMode == mode;
        final icon = mode == 'Car' ? Icons.directions_car : Icons.two_wheeler;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: mode == 'Car' ? 10 : 0),
            child: GestureDetector(
              onTap: () => setState(() {
                selectedMode = mode;
                if (mode == 'Bike') isAC = false;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF00897B)
                      : const Color(0xFFF1F4F7),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF00897B)
                        : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon,
                        size: 18,
                        color:
                        isSelected ? Colors.white : Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Text(mode,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : Colors.grey.shade600)),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _acToggle() {
    return GestureDetector(
      onTap: () => setState(() => isAC = !isAC),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isAC
              ? const Color(0xFF00897B).withOpacity(0.08)
              : const Color(0xFFF1F4F7),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isAC ? const Color(0xFF00897B) : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.ac_unit,
                size: 18,
                color: isAC ? const Color(0xFF00897B) : Colors.grey.shade500),
            const SizedBox(width: 10),
            Text('AC Preferred',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isAC
                        ? const Color(0xFF00897B)
                        : Colors.grey.shade600)),
            const Spacer(),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 22,
              decoration: BoxDecoration(
                color: isAC ? const Color(0xFF00897B) : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(11),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment:
                isAC ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _genderDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F7),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedGender,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down,
              color: Color(0xFF00897B), size: 20),
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF212121)),
          onChanged: (val) => setState(() => selectedGender = val!),
          items: ['Any', 'Male', 'Female'].map((g) {
            return DropdownMenuItem(
              value: g,
              child: Row(
                children: [
                  Icon(
                    g == 'Male'
                        ? Icons.male
                        : g == 'Female'
                        ? Icons.female
                        : Icons.people_outline,
                    size: 16,
                    color: const Color(0xFF00897B),
                  ),
                  const SizedBox(width: 6),
                  Text(g),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _seatsStepper() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F7),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Row(
        children: [
          Icon(Icons.event_seat, size: 16, color: Color(0xFF00897B)),
          SizedBox(width: 6),
          Text('1 seat',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF212121))),
        ],
      ),
    );
  }

  // ─── UPDATED DRAWER ───────────────────────────────────────────────────────
  Widget _buildDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.75,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            // Header — reads from UserSession now
            Container(
              padding: const EdgeInsets.only(
                  top: 60, left: 20, right: 20, bottom: 30),
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF00897B),
                borderRadius:
                BorderRadius.only(topRight: Radius.circular(30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 35,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person,
                        size: 45, color: Color(0xFF00897B)),
                  ),
                  const SizedBox(height: 15),
                  // ↓ was hardcoded 'Ghazfa Batool' — now from UserSession
                  Text(UserSession.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  // ↓ was hardcoded 'Student ID: 12345' — now from UserSession
                  Text('Student ID: ${UserSession.studentId}',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14)),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ── NEW: My Profile tile ──
            _drawerTile(
              icon: Icons.person_outline,
              label: 'My Profile',
              onTap: () {
                Navigator.pop(context); // close drawer first
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PassengerProfileScreen()),
                );
              },
            ),

            // ── NEW: Ride History tile ──
            _drawerTile(
              icon: Icons.history_rounded,
              label: 'Ride History',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const RideHistoryScreen()),
                );
              },
            ),

            // ── My Booked Rides tile ──
            _drawerTile(
              icon: Icons.directions_car_filled_outlined,
              label: 'My Booked Rides',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const RideHistoryScreen()),
                );
              },
            ),

            // ── Notifications tile ──
            _drawerTile(
              icon: Icons.notifications_outlined,
              label: 'Notifications',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const NotificationsScreen()));
              },
            ),

            // ── Driver mode: switch if registered, otherwise register ──
            if (_hasDriverRole)
              _drawerTile(
                icon: Icons.directions_car_outlined,
                label: 'Switch to Driver Mode',
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await AuthService.switchMode('driver');
                    UserSession.activeRole = 'driver';
                    await UserSession.save();
                    if (!context.mounted) return;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const OfferRidePage()),
                      (route) => false,
                    );
                  } catch (e) {
                    TopRightAlert.show(context,
                        title: 'Switch Failed',
                        message: e.toString().replaceFirst('Exception: ', ''),
                        isError: true);
                  }
                },
              )
            else
              _drawerTile(
                icon: Icons.badge_outlined,
                label: 'Become a Driver',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DriverRiderRegisterPage(isUpgrade: true),
                    ),
                  );
                },
              ),

            const Spacer(),

            // Logout
            Padding(
              padding: const EdgeInsets.all(20),
              child: InkWell(
                onTap: () {
                  UserSession.clear();
                  TopRightAlert.show(
                    context,
                    title: 'Signed out',
                    message: 'You have been signed out.',
                    isError: false,
                  );
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const HamrahLoginPage()),
                        (route) => false,
                  );
                },
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 15, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.logout_rounded, color: Colors.red),
                      SizedBox(width: 15),
                      Text('Logout',
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _drawerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
      leading:
      Icon(icon, color: const Color(0xFF00897B), size: 22),
      title: Text(label,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF212121))),
      trailing: const Icon(Icons.chevron_right,
          color: Colors.grey, size: 20),
      onTap: onTap,
    );
  }
}