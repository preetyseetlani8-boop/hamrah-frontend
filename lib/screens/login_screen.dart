// lib/screens/login_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../widgets/top_right_alert.dart';
import '../services/UserSession.dart';
import '../services/auth_service.dart';
import '../config/api_config.dart';
import 'Ridebook.dart';
import 'offerride.dart';
import 'signup_screen.dart';
import 'ForgotPssword.dart';
import 'RateDriver.dart';
import '../services/firebase_notification_service.dart';

class HamrahLoginPage extends StatefulWidget {
  final String? sessionMessage;
  const HamrahLoginPage({super.key, this.sessionMessage});

  @override
  State<HamrahLoginPage> createState() => _HamrahLoginPageState();
}

class _HamrahLoginPageState extends State<HamrahLoginPage> {
  final TextEditingController emailController    = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _isLoading   = false;
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    if (widget.sessionMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.sessionMessage!),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final email    = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      TopRightAlert.show(context,
          title: 'Required fields',
          message: 'Email and password are required.',
          isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await AuthService.login(email, password);
      if (!mounted) return;

      final token = (result['access_token'] ?? result['token'])?.toString() ?? '';
      final success = result['success'] == true || token.isNotEmpty;

      if (!success) {
        TopRightAlert.show(
          context,
          title: 'Login Failed',
          message: result['message']?.toString() ?? 'Invalid email or password.',
          isError: true,
        );
        return;
      }

      UserSession.token = token;
      UserSession.email = email;

      // Fetch full user profile
      final me = await AuthService.fetchMe();
      UserSession.name      = '${me['first_name'] ?? ''} ${me['last_name'] ?? ''}'.trim();
      UserSession.studentId = me['dsu_reg_id']?.toString() ?? '';
      UserSession.phone     = me['phone_number']?.toString() ?? '';
      UserSession.email     = me['email']?.toString() ?? email;
      UserSession.userId    = me['id']?.toString() ?? '';

      UserSession.registeredRoles = [];
      if (me['is_passenger'] == true) UserSession.registeredRoles.add('passenger');
      if (me['is_driver']    == true) UserSession.registeredRoles.add('driver');

      UserSession.totalRides = me['total_rides'] as int? ?? 0;

      final vehicles = me['vehicles'] as List?;
      if (vehicles != null && vehicles.isNotEmpty) {
        final car = vehicles.firstWhere(
          (v) => v['mode_of_transport'] == 'car',
          orElse: () => vehicles[0],
        );
        UserSession.vehicleId     = car['id'] as int? ?? 0;
        UserSession.vehicleMode   = car['mode_of_transport']?.toString() ?? '';
        UserSession.vehicleNumber = car['vehicle_number']?.toString() ?? '';
        UserSession.vehicleModel  = car['vehicle_model']?.toString() ?? '';
        UserSession.vehicleColour = car['vehicle_colour']?.toString() ?? '';
      }

      if (me['is_driver'] == true) {
        try {
          final userId = me['id'] as int? ?? 0;
          final ratingRes = await http.get(
            ApiConfig.uri('/ratings/driver/$userId'),
            headers: ApiConfig.jsonHeaders(),
          );
          if (ratingRes.statusCode == 200) {
            final rData = jsonDecode(ratingRes.body);
            UserSession.driverRating = (rData['average_rating'] ?? 0.0).toDouble();
            UserSession.totalRatings = rData['total_ratings'] as int? ?? 0;
          }
        } catch (_) {}
      }

      await UserSession.save();
      FirebaseNotificationService.instance.saveTokenToBackend();

      TopRightAlert.show(
        context,
        title: 'Signed in',
        message: 'Welcome back.',
        isError: false,
      );

      final roles = UserSession.registeredRoles;

      if (roles.contains('driver') && roles.contains('passenger')) {
        // First show role picker for users with both roles
        _showRolePicker();
      } else if (roles.contains('driver')) {
        UserSession.activeRole = 'driver';
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const OfferRidePage()),
        );
      } else {
        UserSession.activeRole = 'passenger';
        // Check for unrated completed rides (passenger only)
        final unratedRides = await _fetchUnratedRides();
        if (unratedRides.isNotEmpty && mounted) {
          // Show rating screen for the first unrated ride, with the rest queued
          final firstRide = unratedRides.first;
          final restRides = unratedRides.sublist(1);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => RateDriverScreen(
                driver: {
                  'name': firstRide['driver_name'] ?? 'Driver',
                  'ride_id': firstRide['ride_id'],
                  'vehicle': 'Car',
                  'plate': firstRide['vehicle_number'] ?? '',
                  'price': 'Rs. ${firstRide['fare'] ?? 0}',
                  'from': firstRide['from_address'] ?? '',
                  'to': firstRide['to_address'] ?? '',
                },
                remainingUnrated: restRides,
              ),
            ),
          );
          return;
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const RideSearchScreen()),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      TopRightAlert.show(
        context,
        title: 'Error',
        message: e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Fetch all unrated completed rides for the current passenger
  Future<List<Map<String, dynamic>>> _fetchUnratedRides() async {
    try {
      final response = await http.get(
        ApiConfig.uri('/ratings/unrated'),
        headers: ApiConfig.jsonHeaders(),
      );
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List;
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  void _showRolePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10)),
            ),
            const SizedBox(height: 20),
            const Text('Select role',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF212121))),
            const SizedBox(height: 6),
            Text('This account has passenger and driver access.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _roleCard(
                    icon: Icons.hail_outlined,
                    label: 'Passenger',
                    subtitle: 'Book rides',
                    onTap: () async {
                      Navigator.pop(ctx);
                      UserSession.activeRole = 'passenger';
                      // Check for unrated rides after selecting passenger
                      final unratedRides = await _fetchUnratedRides();
                      if (unratedRides.isNotEmpty && mounted) {
                        final firstRide = unratedRides.first;
                        final restRides = unratedRides.sublist(1);
                        Navigator.pushReplacement(context,
                            MaterialPageRoute(builder: (_) => RateDriverScreen(
                              driver: {
                                'name': firstRide['driver_name'] ?? 'Driver',
                                'ride_id': firstRide['ride_id'],
                                'vehicle': 'Car',
                                'plate': firstRide['vehicle_number'] ?? '',
                                'price': 'Rs. ${firstRide['fare'] ?? 0}',
                                'from': firstRide['from_address'] ?? '',
                                'to': firstRide['to_address'] ?? '',
                              },
                              remainingUnrated: restRides,
                            ))
                        );
                      } else if (mounted) {
                        Navigator.pushReplacement(context,
                            MaterialPageRoute(builder: (_) => const RideSearchScreen()));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _roleCard(
                    icon: Icons.directions_car_outlined,
                    label: 'Driver',
                    subtitle: 'Manage rides',
                    onTap: () {
                      Navigator.pop(ctx);
                      UserSession.activeRole = 'driver';
                      Navigator.pushReplacement(context,
                          MaterialPageRoute(builder: (_) => const OfferRidePage()));
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleCard({required IconData icon, required String label,
      required String subtitle, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFE0F2F1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF00897B).withOpacity(0.3)),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white,
              child: Icon(icon, color: const Color(0xFF00897B), size: 28),
            ),
            const SizedBox(height: 10),
            Text(label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold,
                    color: Color(0xFF00897B))),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  Image.asset('assets/logo.png', height: 120),
                  const SizedBox(height: 10),
                  const Text('Sign in',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00897B))),
                  const SizedBox(height: 30),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10))
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTextField(
                            controller: emailController,
                            label: 'Registration ID',
                            icon: Icons.email_outlined),
                        const SizedBox(height: 20),
                        _buildTextField(
                            controller: passwordController,
                            label: 'Password',
                            icon: Icons.lock_outline,
                            isPassword: true),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                            child: const Text('Forgot Password?',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 55,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00897B),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15)),
                              elevation: 5,
                            ),
                            onPressed: _isLoading ? null : _handleLogin,
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text('Sign in',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account? ",
                          style: TextStyle(color: Colors.black54)),
                      GestureDetector(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const SignupChoicePage())),
                        child: const Text('Create account',
                            style: TextStyle(
                                color: Color(0xFF00897B),
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword ? _obscureText : false,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF00897B)),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureText = !_obscureText))
            : null,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF00897B), width: 1.5),
        ),
      ),
    );
  }
}