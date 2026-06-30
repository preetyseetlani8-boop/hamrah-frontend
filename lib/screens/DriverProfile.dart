// lib/screens/driver_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../widgets/top_right_alert.dart';
import '../services/UserSession.dart';
import '../services/auth_service.dart';
import '../config/api_config.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _studentIdController;

  // Dynamic lists to handle multiple vehicles simultaneously
  final List<TextEditingController> _vehicleControllers = [];
  final List<TextEditingController> _plateControllers = [];
  final List<TextEditingController> _colorControllers = [];
  final List<int?> _vehicleIds = [];
  final List<String> _modeOfTransports = [];

  bool _isEditing = false;
  bool _loadingProfile = true;

  @override
  void initState() {
    super.initState();
    final parts = UserSession.name.split(' ');
    _firstNameController =
        TextEditingController(text: parts.isNotEmpty ? parts[0] : '');
    _lastNameController =
        TextEditingController(text: parts.length > 1 ? parts[1] : '');
    _phoneController =
        TextEditingController(text: UserSession.phone);
    _emailController =
        TextEditingController(text: UserSession.email);
    _studentIdController =
        TextEditingController(text: UserSession.studentId);

    // Seed initial vehicle from current session profile fallback
    _addVehicleFields(
      id: UserSession.vehicleId > 0 ? UserSession.vehicleId : null,
      model: UserSession.vehicleModel,
      plate: UserSession.vehicleNumber,
      color: UserSession.vehicleColour,
      mode: UserSession.vehicleMode.isNotEmpty ? UserSession.vehicleMode : 'car',
    );

    _loadProfile();
  }

  // Helper method to add a new set of controllers for a vehicle instance
  void _addVehicleFields({int? id, String model = '', String plate = '', String color = '', String mode = 'car'}) {
    setState(() {
      _vehicleControllers.add(TextEditingController(text: model));
      _plateControllers.add(TextEditingController(text: plate));
      _colorControllers.add(TextEditingController(text: color));
      _vehicleIds.add(id);
      _modeOfTransports.add(mode);
    });
  }

  // Helper method to remove a vehicle set from form arrays
  void _removeVehicleFields(int index) {
    if (_vehicleControllers.length <= 1) {
      TopRightAlert.show(context,
          title: 'Action Denied',
          message: 'You must keep at least one vehicle registered.',
          isError: true);
      return;
    }
    setState(() {
      _vehicleControllers[index].dispose();
      _plateControllers[index].dispose();
      _colorControllers[index].dispose();

      _vehicleControllers.removeAt(index);
      _plateControllers.removeAt(index);
      _colorControllers.removeAt(index);
      _vehicleIds.removeAt(index);
      _modeOfTransports.removeAt(index);
    });
  }

  Future<void> _loadProfile() async {
    try {
      await AuthService.syncSessionFromMe();
      final me = await AuthService.fetchMe();
      final userId = me['id'] as int? ?? 0;
      if (userId > 0) {
        try {
          final ratingRes = await http.get(
            ApiConfig.uri('/ratings/driver/$userId'),
            headers: ApiConfig.jsonHeaders(),
          );
          if (ratingRes.statusCode == 200) {
            final rData = jsonDecode(ratingRes.body);
            UserSession.driverRating =
                (rData['average_rating'] ?? 0.0).toDouble();
            UserSession.totalRatings = rData['total_ratings'] as int? ?? 0;
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        final nameParts =
            '${me['first_name'] ?? ''} ${me['last_name'] ?? ''}'.trim().split(' ');
        _firstNameController.text = nameParts.isNotEmpty ? nameParts[0] : '';
        _lastNameController.text = nameParts.length > 1 ? nameParts[1] : '';
        _phoneController.text = me['phone_number']?.toString() ?? '';
        _emailController.text = me['email']?.toString() ?? '';
        _studentIdController.text = me['dsu_reg_id']?.toString() ?? '';

        // Populate vehicles from nested backend schema array if present
        if (me['vehicles'] != null && me['vehicles'] is List) {
          // Clear current temporary fields
          for (var c in _vehicleControllers) {c.dispose();}
          for (var c in _plateControllers) {c.dispose();}
          for (var c in _colorControllers) {c.dispose();}
          _vehicleControllers.clear();
          _plateControllers.clear();
          _colorControllers.clear();
          _vehicleIds.clear();
          _modeOfTransports.clear();

          final List dynamicVehicles = me['vehicles'];
          for (var v in dynamicVehicles) {
            _addVehicleFields(
              id: v['id'] as int?,
              model: v['vehicle_model'] ?? v['model'] ?? '',
              plate: v['vehicle_number'] ?? v['plate_number'] ?? '',
              color: v['vehicle_colour'] ?? v['color'] ?? '',
              mode: v['mode_of_transport'] ?? 'car',
            );
          }
        }

        _loadingProfile = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _studentIdController.dispose();

    // Iterative clean disposal of dynamic lists
    for (var controller in _vehicleControllers) { controller.dispose(); }
    for (var controller in _plateControllers) { controller.dispose(); }
    for (var controller in _colorControllers) { controller.dispose(); }
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (_firstNameController.text.isEmpty ||
        _lastNameController.text.isEmpty) {
      TopRightAlert.show(context,
          title: 'Name Required',
          message: 'Enter first and last name.',
          isError: true);
      return;
    }

    // Verify all current vehicle inputs are filled properly
    for (int i = 0; i < _vehicleControllers.length; i++) {
      if (_vehicleControllers[i].text.trim().isEmpty ||
          _plateControllers[i].text.trim().isEmpty) {
        TopRightAlert.show(context,
            title: 'Incomplete Vehicle Info',
            message: 'Please complete all fields for Vehicle #${i + 1}.',
            isError: true);
        return;
      }
    }

    try {
      // Map controllers into an array layout payload
      final List<Map<String, dynamic>> vehiclePayload = [];
      for (int i = 0; i < _vehicleControllers.length; i++) {
        vehiclePayload.add({
          if (_vehicleIds[i] != null) 'id': _vehicleIds[i],
          'vehicle_model': _vehicleControllers[i].text.trim(),
          'vehicle_number': _plateControllers[i].text.trim(),
          'vehicle_colour': _colorControllers[i].text.trim(),
          'mode_of_transport': _modeOfTransports[i],
        });
      }

      // Sync vehicles first
      final syncRes = await http.put(
        ApiConfig.uri('/vehicles/sync'),
        headers: ApiConfig.jsonHeaders(),
        body: jsonEncode(vehiclePayload),
      );
      if (syncRes.statusCode != 200) {
        final errData = jsonDecode(syncRes.body);
        throw Exception(errData['detail'] ?? 'Failed to sync vehicles.');
      }

      // Pass profile fields to update profile
      await AuthService.updateProfile(
        firstName: _firstNameController.text.trim(),
        lastName:  _lastNameController.text.trim(),
        phone:     _phoneController.text.trim(),
      );

      UserSession.name  = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}';
      UserSession.phone = _phoneController.text.trim();

      // Sync local session information
      await AuthService.syncSessionFromMe();

      setState(() => _isEditing = false);
      _loadProfile(); // reload to get any database-generated IDs
      TopRightAlert.show(context,
          title: 'Profile Updated',
          message: 'Your changes have been saved.',
          isError: false);
    } catch (e) {
      TopRightAlert.show(context,
          title: 'Update Failed',
          message: e.toString().replaceFirst('Exception: ', ''),
          isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/doodles1.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new,
                          color: Color(0xFF00897B)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text('Driver Profile',
                          style: TextStyle(
                              color: Color(0xFF00897B),
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: () {
                        if (_isEditing) {
                          _saveChanges();
                        } else {
                          setState(() => _isEditing = true);
                        }
                      },
                      child: Text(
                        _isEditing ? 'Save' : 'Edit',
                        style: const TextStyle(
                            color: Color(0xFF00897B),
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: _loadingProfile
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF00897B)))
                    : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),

                      // Avatar
                      Stack(
                        children: [
                          const CircleAvatar(
                            radius: 52,
                            backgroundColor: Color(0xFFE0F2F1),
                            child: Icon(Icons.directions_car,
                                size: 52, color: Color(0xFF00897B)),
                          ),
                          if (_isEditing)
                            const Positioned(
                              bottom: 0,
                              right: 0,
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: Color(0xFF00897B),
                                child: Icon(Icons.camera_alt,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(UserSession.name,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF212121))),
                      Text('Driver / Rider',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500)),
                      const SizedBox(height: 6),
                      // Rating badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded,
                                color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${UserSession.driverRating.toStringAsFixed(1)} rating',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.amber),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── Personal info section ──
                      _sectionHeader('Personal Information'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildField(
                                controller: _firstNameController,
                                icon: Icons.person_outline,
                                label: 'First Name',
                                enabled: _isEditing),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildField(
                                controller: _lastNameController,
                                icon: Icons.person_outline,
                                label: 'Last Name',
                                enabled: _isEditing),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildField(
                          controller: _studentIdController,
                          icon: Icons.badge_outlined,
                          label: 'DSU Rider ID',
                          enabled: _isEditing,
                          keyboardType: TextInputType.number),
                      const SizedBox(height: 12),
                      _buildField(
                          controller: _phoneController,
                          icon: Icons.phone_android_outlined,
                          label: 'Phone Number',
                          enabled: _isEditing,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ]),
                      const SizedBox(height: 12),
                      _buildField(
                          controller: _emailController,
                          icon: Icons.email_outlined,
                          label: 'Email Address',
                          enabled: _isEditing,
                          keyboardType: TextInputType.emailAddress),
                      const SizedBox(height: 24),

                      // ── Dynamic Vehicle info section ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _sectionHeader('Vehicle Information'),
                          if (_isEditing)
                            TextButton.icon(
                              onPressed: () => _addVehicleFields(),
                              icon: const Icon(Icons.add, size: 16, color: Color(0xFF00897B)),
                              label: const Text(
                                'Add Vehicle',
                                style: TextStyle(
                                  color: Color(0xFF00897B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13
                                ),
                              ),
                            )
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Generates dynamic input blocks for all added vehicles
                      Column(
                        children: List.generate(_vehicleControllers.length, (index) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: Colors.grey.shade200)
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Vehicle #${index + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade700
                                      ),
                                    ),
                                    if (_isEditing && _vehicleControllers.length > 1)
                                      GestureDetector(
                                        onTap: () => _removeVehicleFields(index),
                                        child: const Icon(Icons.remove_circle, color: Colors.redAccent, size: 20),
                                      )
                                  ],
                                ),
                                const SizedBox(height: 10),
                                _buildField(
                                    controller: _vehicleControllers[index],
                                    icon: Icons.directions_car_outlined,
                                    label: 'Car Model',
                                    enabled: _isEditing),
                                const SizedBox(height: 12),
                                _buildDropdownField(
                                    index: index,
                                    enabled: _isEditing),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildField(
                                          controller: _plateControllers[index],
                                          icon: Icons.confirmation_number_outlined,
                                          label: 'Plate No.',
                                          enabled: _isEditing),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildField(
                                          controller: _colorControllers[index],
                                          icon: Icons.color_lens_outlined,
                                          label: 'Color',
                                          enabled: _isEditing),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),

                      // Stats
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10)
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment:
                          MainAxisAlignment.spaceAround,
                          children: [
                            _statItem('${UserSession.totalRides}', 'Total\nRides'),
                            _divider(),
                            _statItem(UserSession.driverRating.toStringAsFixed(1), 'Avg\nRating'),
                            _divider(),
                            _statItem('Rs.\n—', 'Earned\nTotal'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(title,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF00897B))),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required bool enabled,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF212121)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            fontSize: 12,
            color: enabled
                ? const Color(0xFF00897B)
                : Colors.grey.shade500),
        prefixIcon: Icon(icon, color: const Color(0xFF00897B), size: 20),
        filled: true,
        fillColor: enabled
            ? Colors.white.withOpacity(0.95)
            : Colors.white.withOpacity(0.6),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide:
          const BorderSide(color: Color(0xFF00897B), width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildDropdownField({required int index, required bool enabled}) {
    final mode = _modeOfTransports[index];
    if (!enabled) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            const Icon(Icons.commute_outlined, color: Color(0xFF00897B), size: 20),
            const SizedBox(width: 12),
            Text(
              'Transport Mode: ${mode.toUpperCase()}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF212121),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(15),
      ),
      child: DropdownButtonFormField<String>(
        decoration: const InputDecoration(
          border: InputBorder.none,
          prefixIcon: Icon(Icons.commute_outlined, color: Color(0xFF00897B), size: 20),
          labelText: 'Transport Mode',
          labelStyle: TextStyle(fontSize: 12, color: Color(0xFF00897B)),
        ),
        value: mode == 'car' || mode == 'bike' ? mode : 'car',
        items: const [
          DropdownMenuItem(value: 'car', child: Text('Car')),
          DropdownMenuItem(value: 'bike', child: Text('Bike')),
        ],
        onChanged: (v) {
          if (v != null) {
            setState(() {
              _modeOfTransports[index] = v;
            });
          }
        },
      ),
    );
  }

  Widget _statItem(String value, String label) {
    return Column(
      children: [
        Text(value,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF00897B))),
        const SizedBox(height: 4),
        Text(label,
            textAlign: TextAlign.center,
            style:
            TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 36, color: Colors.grey.shade200);
}