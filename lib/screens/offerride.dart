// lib/screens/offerride.dart
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../widgets/top_right_alert.dart';
import '../widgets/osm_location_picker.dart';
import '../widgets/location_autocomplete.dart';   // ← NEW
import '../services/UserSession.dart';
import '../services/ride_services.dart';
import '../services/auth_service.dart';
import '../config/api_config.dart';
import 'login_screen.dart';
import 'DriverDashboard.dart';
import 'Notifications.dart';
import 'Ridebook.dart';

class OfferRidePage extends StatefulWidget {
  const OfferRidePage({super.key});

  @override
  State<OfferRidePage> createState() => _OfferRidePageState();
}

class _OfferRidePageState extends State<OfferRidePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _hasPassengerRole = false;

  final TextEditingController fromController  = TextEditingController();
  final TextEditingController toController    = TextEditingController();
  final TextEditingController fareController  = TextEditingController();
  final TextEditingController seatsController = TextEditingController();
  LatLng? _pickupPoint;
  LatLng? _destinationPoint;

  // Extra pickup points for multiple passengers
  List<Map<String, dynamic>> _driverVehicles = [];
  int? _selectedVehicleId;
  bool _loadingVehicles = true;

  @override
  void initState() {
    super.initState();
    _hasPassengerRole = UserSession.registeredRoles.contains('passenger');
    _refreshUserRoles();
    _fetchVehicles();
  }

  Future<void> _fetchVehicles() async {
    try {
      final response = await http.get(
        ApiConfig.uri(ApiConfig.vehiclesList),
        headers: ApiConfig.jsonHeaders(),
      );
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        setState(() {
          _driverVehicles = data.map((v) => Map<String, dynamic>.from(v)).toList();
          if (_driverVehicles.isNotEmpty) {
            _selectedVehicleId = _driverVehicles[0]['id'] as int?;
          }
          _loadingVehicles = false;
        });
      } else {
        setState(() => _loadingVehicles = false);
      }
    } catch (_) {
      setState(() => _loadingVehicles = false);
    }
  }

  Future<void> _refreshUserRoles() async {
    try {
      await AuthService.syncSessionFromMe();
      if (!mounted) return;
      setState(() {
        _hasPassengerRole = UserSession.registeredRoles.contains('passenger');
      });
    } catch (_) {}
  }

  // Extra pickup points for multiple passengers
  final List<Map<String, dynamic>> _extraPickups = [];

  DateTime selectedDate  = DateTime.now();
  TimeOfDay selectedTime = TimeOfDay.now();
  String selectedAC      = 'AC';
  String selectedGender  = 'All';
  bool _isPosting        = false;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 1),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF00897B),
            onPrimary: Colors.white,
            onSurface: Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: selectedTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF00897B),
            onSurface: Colors.black,
          ),
        ),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        ),
      ),
    );
    if (picked != null) setState(() => selectedTime = picked);
  }

  Future<void> _addExtraPickup() async {
    final TextEditingController ctrl = TextEditingController();
    LatLng? selected;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Add Pickup Point',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                    color: Color(0xFF00897B))),
            const SizedBox(height: 12),
            LocationAutocomplete(
              controller: ctrl,
              label: 'Pickup Location',
              hint: 'Search pickup location',
              icon: Icons.add_location_alt,
              iconColor: const Color(0xFF00897B),
              onLocationSelected: (coords, name) {
                selected = coords;
                ctrl.text = name;
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  if (selected != null && ctrl.text.isNotEmpty) {
                    setState(() => _extraPickups.add({
                      'address': ctrl.text,
                      'lat': selected!.latitude,
                      'lng': selected!.longitude,
                      'order_index': _extraPickups.length + 1,
                    }));
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add', style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _postRide() async {
    if (_selectedVehicleId == null) {
      TopRightAlert.show(context,
          title: 'Vehicle Required',
          message: 'Please select a vehicle to post this ride.',
          isError: true);
      return;
    }

    final selectedVehicle = _driverVehicles.firstWhere((v) => v['id'] == _selectedVehicleId);
    final isBike = selectedVehicle['mode_of_transport'] == 'bike';

    if (fromController.text.isEmpty ||
        toController.text.isEmpty ||
        fareController.text.isEmpty ||
        (!isBike && seatsController.text.isEmpty)) {
      TopRightAlert.show(context,
          title: 'Details Missing',
          message: 'Complete all required fields.',
          isError: true);
      return;
    }
    if (_pickupPoint == null || _destinationPoint == null) {
      TopRightAlert.show(context,
          title: 'Invalid Location',
          message: 'Select locations from suggestions.',
          isError: true);
      return;
    }

    setState(() => _isPosting = true);

    try {
      final timeStr =
          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

      // Combine date + time into departure datetime
      final departure = DateTime(
        selectedDate.year, selectedDate.month, selectedDate.day,
        selectedTime.hour, selectedTime.minute,
      );

      await RideService.offerRide(
        vehicleId:     _selectedVehicleId!,
        fromAddress:   fromController.text.trim(),
        toAddress:     toController.text.trim(),
        fromLat:       _pickupPoint!.latitude,
        fromLng:       _pickupPoint!.longitude,
        toLat:         _destinationPoint!.latitude,
        toLng:         _destinationPoint!.longitude,
        fare:          double.tryParse(fareController.text.trim()) ?? 0,
        seats:         isBike ? 1 : (int.tryParse(seatsController.text.trim()) ?? 1),
        ac:            selectedAC == 'AC',
        genderFilter:  selectedGender == 'All' ? 'any' : selectedGender,
        departureTime: departure,
        extraPickups:  _extraPickups,
        modeOfTransport: selectedVehicle['mode_of_transport'] ?? 'car',
      );

      if (!mounted) return;

      TopRightAlert.show(context,
          title: 'Ride published',
          message: 'Your ride is now available.',
          isError: false);

      fromController.clear();
      toController.clear();
      fareController.clear();
      seatsController.clear();
      setState(() {
        _pickupPoint = null;
        _destinationPoint = null;
      });

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DriverDashboardScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      TopRightAlert.show(context,
          title: 'Failed to Post Ride',
          message: e.toString().replaceFirst('Exception: ', ''),
          isError: true);
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7F9),
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          Positioned(
            top: 0, left: 0, right: 0,
            height: MediaQuery.of(context).size.height * 0.45,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(24),
              ),
              child: OsmLocationPicker(
                pickup: _pickupPoint,
                destination: _destinationPoint,
                onPickupChanged: (point) {
                  setState(() {
                    _pickupPoint = point;
                    fromController.text =
                    '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
                  });
                },
                onDestinationChanged: (point) {
                  setState(() {
                    _destinationPoint = point;
                    toController.text =
                    '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
                  });
                },
              ),
            ),
          ),

          // Menu button
          Positioned(
            top: 40, left: 20,
            child: Material(
              elevation: 4,
              shape: const CircleBorder(),
              color: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.menu, color: Color(0xFF00897B)),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
            ),
          ),

          // Form sheet
          DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.55,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                            width: 50, height: 5,
                            decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(10))),
                      ),
                      const SizedBox(height: 20),
                      const Text('Post a ride',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00897B))),
                      const SizedBox(height: 20),

                      // Vehicle Selection Block
                      const Text(
                        'Select Vehicle',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00897B)),
                      ),
                      const SizedBox(height: 10),
                      _loadingVehicles
                          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00897B)))
                          : _driverVehicles.isEmpty
                              ? const Text('No vehicles available. Please update your profile.', style: TextStyle(color: Colors.red))
                              : Column(
                                  children: _driverVehicles.map((v) {
                                    final isSelected = _selectedVehicleId == v['id'];
                                    return GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedVehicleId = v['id'] as int?;
                                        });
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isSelected ? const Color(0xFFE0F2F1) : const Color(0xFFF1F4F7),
                                          borderRadius: BorderRadius.circular(15),
                                          border: Border.all(
                                            color: isSelected ? const Color(0xFF00897B) : Colors.transparent,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Radio<int>(
                                              value: v['id'] as int,
                                              groupValue: _selectedVehicleId,
                                              activeColor: const Color(0xFF00897B),
                                              onChanged: (val) {
                                                setState(() {
                                                  _selectedVehicleId = val;
                                                });
                                              },
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    v['vehicle_model'] ?? 'Unknown Model',
                                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                                  ),
                                                  Text(v['vehicle_number'] ?? ''),
                                                  Text(
                                                    v['mode_of_transport']?.toString().toUpperCase() ?? '',
                                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                      const SizedBox(height: 20),

                      // Location Autocomplete fields
                      LocationAutocomplete(
                        controller: fromController,
                        label: 'Pickup Point',
                        hint: 'Search pickup location',
                        icon: Icons.my_location,
                        iconColor: const Color(0xFF00897B),
                        onLocationSelected: (coordinates, displayName) {
                          setState(() => _pickupPoint = coordinates);
                        },
                      ),
                      const SizedBox(height: 12),
                      LocationAutocomplete(
                        controller: toController,
                        label: 'Drop-off Point',
                        hint: 'Search drop-off location',
                        icon: Icons.location_on,
                        iconColor: Colors.redAccent,
                        onLocationSelected: (coordinates, displayName) {
                          setState(() => _destinationPoint = coordinates);
                        },
                      ),
                      // ── Extra pickup points ──
                      const SizedBox(height: 8),
                      if (_extraPickups.isNotEmpty) ...[
                        ..._extraPickups.asMap().entries.map((e) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2F1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(children: [
                            const Icon(Icons.add_location_alt, size: 16, color: Color(0xFF00897B)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(
                              e.value['address'] ?? '',
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            )),
                            GestureDetector(
                              onTap: () => setState(() => _extraPickups.removeAt(e.key)),
                              child: const Icon(Icons.close, size: 16, color: Colors.red),
                            ),
                          ]),
                        )),
                      ],
                      TextButton.icon(
                        onPressed: _addExtraPickup,
                        icon: const Icon(Icons.add_location, color: Color(0xFF00897B), size: 18),
                        label: const Text('Add Pickup Point',
                            style: TextStyle(color: Color(0xFF00897B), fontSize: 13)),
                      ),
                      // ──────────────────────────────────────────────────

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(child: _buildPickerTile(
                              Icons.calendar_today,
                              '${selectedDate.day}-${selectedDate.month}-${selectedDate.year}',
                              _pickDate)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildPickerTile(
                              Icons.access_time,
                              selectedTime.format(context),
                              _pickTime)),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(child: _buildTextField(
                            Icons.payments, 'Fare', fareController,
                              keyboardType: TextInputType.number)),
                          if (_selectedVehicleId != null &&
                              _driverVehicles.isNotEmpty &&
                              _driverVehicles.firstWhere((v) => v['id'] == _selectedVehicleId, orElse: () => _driverVehicles[0])['mode_of_transport'] != 'bike') ...[
                            const SizedBox(width: 12),
                            Expanded(child: _buildTextField(
                                Icons.event_seat, 'Seats', seatsController,
                                keyboardType: TextInputType.number)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          if (_selectedVehicleId != null &&
                              _driverVehicles.isNotEmpty &&
                              _driverVehicles.firstWhere((v) => v['id'] == _selectedVehicleId, orElse: () => _driverVehicles[0])['mode_of_transport'] != 'bike') ...[
                            Expanded(child: _buildDropdown(
                                Icons.ac_unit, ['AC', 'Non-AC'], selectedAC,
                                    (v) => setState(() => selectedAC = v!))),
                            const SizedBox(width: 12),
                          ],
                          Expanded(child: _buildDropdown(
                              Icons.people, ['All', 'Male', 'Female'], selectedGender,
                                  (v) => setState(() => selectedGender = v!))),
                        ],
                      ),
                      const SizedBox(height: 30),

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00897B),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15)),
                          ),
                          onPressed: _isPosting ? null : _postRide,
                          child: const Text('Post ride',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
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

  Widget _buildDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.75,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
            topRight: Radius.circular(30),
            bottomRight: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 60, left: 20, right: 20, bottom: 30),
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFF00897B),
              borderRadius: BorderRadius.only(topRight: Radius.circular(30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 35,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.directions_car, size: 40, color: Color(0xFF00897B)),
                ),
                const SizedBox(height: 15),
                Text(UserSession.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                Text('Rider ID: ${UserSession.studentId}',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8), fontSize: 14)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Driver Mode',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          _drawerTile(Icons.dashboard_outlined, 'Dashboard', () {
            Navigator.pop(context);
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const DriverDashboardScreen()));
          }),
          _drawerTile(Icons.notifications_outlined, 'Notifications', () {
            Navigator.pop(context);
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()));
          }),

          if (_hasPassengerRole)
            _drawerTile(Icons.hail_outlined, 'Switch to Passenger', () async {
              Navigator.pop(context);
              try {
                await AuthService.switchMode('passenger');
                UserSession.activeRole = 'passenger';
                await UserSession.save();
                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const RideSearchScreen()),
                  (route) => false,
                );
              } catch (e) {
                TopRightAlert.show(context,
                    title: 'Switch Failed',
                    message: e.toString().replaceFirst('Exception: ', ''),
                    isError: true);
              }
            })
          else
            _drawerTile(Icons.person_add_outlined, 'Create Passenger Account', () async {
              Navigator.pop(context);
              try {
                await AuthService.enablePassenger();
                await AuthService.syncSessionFromMe();
                UserSession.activeRole = 'passenger';
                await UserSession.save();
                if (!mounted) return;
                setState(() => _hasPassengerRole = true);
                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const RideSearchScreen()),
                  (route) => false,
                );
              } catch (e) {
                TopRightAlert.show(context,
                    title: 'Error',
                    message: e.toString().replaceFirst('Exception: ', ''),
                    isError: true);
              }
            }),

          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Logout',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
            onTap: () {
              UserSession.clear();
              TopRightAlert.show(context,
                  title: 'Signed out',
                  message: 'You have been signed out.',
                  isError: false);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const HamrahLoginPage()),
                    (route) => false,
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _drawerTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
      leading: Icon(icon, color: const Color(0xFF00897B), size: 22),
      title: Text(label,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF212121))),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      onTap: onTap,
    );
  }

  // Kept only for Fare and Seats fields
  Widget _buildTextField(IconData icon, String hint,
      TextEditingController controller, {TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF00897B)),
        prefixText: hint == 'Fare' ? 'PKR ' : null,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF1F4F7),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildPickerTile(IconData icon, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
        decoration: BoxDecoration(
            color: const Color(0xFFF1F4F7),
            borderRadius: BorderRadius.circular(15)),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF00897B), size: 20),
            const SizedBox(width: 10),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(IconData icon, List<String> items, String value,
      Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: const Color(0xFFF1F4F7),
          borderRadius: BorderRadius.circular(15)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          onChanged: onChanged,
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
        ),
      ),
    );
  }
}