// lib/screens/passenger_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/top_right_alert.dart';
import '../services/UserSession.dart';
import '../services/auth_service.dart';
import 'regRiderDriver.dart';
import 'offerride.dart';

class PassengerProfileScreen extends StatefulWidget {
  const PassengerProfileScreen({super.key});

  @override
  State<PassengerProfileScreen> createState() =>
      _PassengerProfileScreenState();
}

class _PassengerProfileScreenState extends State<PassengerProfileScreen> {
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _studentIdController;

  bool _isEditing = false;
  bool _hasDriverRole = false;

  @override
  void initState() {
    super.initState();
    _hasDriverRole = UserSession.registeredRoles.contains('driver');
    _refreshUserRoles();
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
  }

  Future<void> _refreshUserRoles() async {
    try {
      await AuthService.syncSessionFromMe();
      if (!mounted) return;
      setState(() {
        _hasDriverRole = UserSession.registeredRoles.contains('driver');
        final parts = UserSession.name.split(' ');
        _firstNameController.text = parts.isNotEmpty ? parts[0] : '';
        _lastNameController.text = parts.length > 1 ? parts[1] : '';
        _phoneController.text = UserSession.phone;
        _emailController.text = UserSession.email;
        _studentIdController.text = UserSession.studentId;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _studentIdController.dispose();
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

    try {
      await AuthService.updateProfile(
        firstName: _firstNameController.text.trim(),
        lastName:  _lastNameController.text.trim(),
        phone:     _phoneController.text.trim(),
      );

      UserSession.name  = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}';
      UserSession.phone = _phoneController.text.trim();
      await UserSession.save();

      setState(() => _isEditing = false);
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
                      child: Text(
                        'My Profile',
                        style: TextStyle(
                            color: Color(0xFF00897B),
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                      ),
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),

                      // Avatar
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 52,
                            backgroundColor: const Color(0xFFE0F2F1),
                            child: const Icon(Icons.person,
                                size: 60, color: Color(0xFF00897B)),
                          ),
                          if (_isEditing)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                const Color(0xFF00897B),
                                child: const Icon(Icons.camera_alt,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      Text(
                        UserSession.name,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF212121)),
                      ),
                      Text(
                        _hasDriverRole ? 'Passenger / Driver' : 'Passenger',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 20),
                      if (_hasDriverRole)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                await AuthService.switchMode('driver');
                                UserSession.activeRole = 'driver';
                                await UserSession.save();
                                if (!context.mounted) return;
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const OfferRidePage()),
                                  (_) => false,
                                );
                              } catch (e) {
                                TopRightAlert.show(context,
                                    title: 'Switch Failed',
                                    message: e.toString().replaceFirst('Exception: ', ''),
                                    isError: true);
                              }
                            },
                            icon: const Icon(Icons.directions_car_outlined,
                                color: Color(0xFF00897B)),
                            label: const Text('Switch to Driver Mode',
                                style: TextStyle(color: Color(0xFF00897B))),
                          ),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const DriverRiderRegisterPage(
                                    isUpgrade: true,
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00897B),
                            ),
                            icon: const Icon(Icons.badge_outlined, color: Colors.white),
                            label: const Text('Become a Driver',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      const SizedBox(height: 20),

                      // Fields
                      Row(
                        children: [
                          Expanded(
                            child: _buildField(
                              controller: _firstNameController,
                              icon: Icons.person_outline,
                              label: 'First Name',
                              enabled: _isEditing,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildField(
                              controller: _lastNameController,
                              icon: Icons.person_outline,
                              label: 'Last Name',
                              enabled: _isEditing,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      _buildField(
                        controller: _studentIdController,
                        icon: Icons.badge_outlined,
                        label: 'DSU Student ID',
                        enabled: _isEditing,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 14),

                      _buildField(
                        controller: _phoneController,
                        icon: Icons.phone_android_outlined,
                        label: 'Phone Number',
                        enabled: _isEditing,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                      ),
                      const SizedBox(height: 14),

                      _buildField(
                        controller: _emailController,
                        icon: Icons.email_outlined,
                        label: 'Email Address',
                        enabled: _isEditing,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 30),
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
        prefixIcon:
        Icon(icon, color: const Color(0xFF00897B), size: 20),
        filled: true,
        fillColor: enabled
            ? Colors.white.withOpacity(0.95)
            : Colors.white.withOpacity(0.6),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(
              color: Color(0xFF00897B), width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

}