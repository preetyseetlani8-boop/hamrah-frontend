// lib/screens/regPassenger.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finalyearproject/screens/otp_verification_screen.dart';
import '../widgets/top_right_alert.dart';
import '../services/registration_service.dart';
import '../services/UserSession.dart';
import 'login_screen.dart';

class PassengerRegisterPage extends StatefulWidget {
  const PassengerRegisterPage({super.key});

  @override
  State<PassengerRegisterPage> createState() => _PassengerRegisterPageState();
}

class _PassengerRegisterPageState extends State<PassengerRegisterPage> {
  bool _obscurePassword = true;
  bool _isLoading = false;
  String _selectedGender = 'Male';

  // Controllers
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController  = TextEditingController();
  final TextEditingController studentIdController = TextEditingController();
  final TextEditingController phoneController     = TextEditingController();
  final TextEditingController cnicController      = TextEditingController();
  final TextEditingController emailController     = TextEditingController();
  final TextEditingController passwordController  = TextEditingController();

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    studentIdController.dispose();
    phoneController.dispose();
    cnicController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // NEXT button — validate all fields then proceed
  // ─────────────────────────────────────────────
  Future<void> _handleNext() async {
    if (firstNameController.text.isEmpty || lastNameController.text.isEmpty) {
      TopRightAlert.show(context,
          title: 'Name Required',
          message: 'Enter first and last name.',
          isError: true);
      return;
    }

    if (studentIdController.text.isEmpty) {
      TopRightAlert.show(context,
          title: 'Student ID Required',
          message: 'Enter student ID.',
          isError: true);
      return;
    }

    if (phoneController.text.isEmpty) {
      TopRightAlert.show(context,
          title: 'Phone Required',
          message: 'Enter phone number.',
          isError: true);
      return;
    }

    if (cnicController.text.isEmpty) {
      TopRightAlert.show(context,
          title: 'CNIC Required',
          message: 'Enter CNIC number.',
          isError: true);
      return;
    }

    if (emailController.text.isEmpty) {
      TopRightAlert.show(context,
          title: 'Email Required',
          message: 'Enter email address.',
          isError: true);
      return;
    }

    if (passwordController.text.isEmpty) {
      TopRightAlert.show(context,
          title: 'Password Required',
          message: 'Enter password.',
          isError: true);
      return;
    }

    // Save to session
    UserSession.name = '${firstNameController.text.trim()} ${lastNameController.text.trim()}';
    UserSession.studentId = studentIdController.text.trim();
    UserSession.phone = phoneController.text.trim();
    UserSession.email = emailController.text.trim();

    RegistrationService.password = passwordController.text.trim();
    RegistrationService.firstName = firstNameController.text.trim();
    RegistrationService.lastName = lastNameController.text.trim();
    RegistrationService.cnicNumber = cnicController.text.trim();

    setState(() => _isLoading = true);

    try {
      await RegistrationService.registerPassenger(
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        studentId: studentIdController.text.trim(),
        phone: phoneController.text.trim(),
        email: emailController.text.trim(),
        cnicNumber: cnicController.text.trim(),
        gender: _selectedGender,
      );

      if (!mounted) return;

      TopRightAlert.show(context,
          title: 'OTP Sent',
          message: 'Check your email for the verification code.',
          isError: false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const OtpVerificationPage(
            registrationRole: 'passenger',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      TopRightAlert.show(context,
          title: 'Registration Failed',
          message: e.toString().replaceFirst('Exception: ', ''),
          isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new,
                          color: Color(0xFF00897B)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text(
                      'Passenger registration',
                      style: TextStyle(
                          color: Color(0xFF00897B),
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const Text('Personal information',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 25),

                      // Name Row
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                                controller: firstNameController,
                                icon: Icons.person_outline,
                                hintText: 'First Name'),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: _buildTextField(
                                controller: lastNameController,
                                icon: Icons.person_outline,
                                hintText: 'Last Name'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),

                      _buildTextField(
                          controller: studentIdController,
                          icon: Icons.badge_outlined,
                          hintText: 'DSU Reg ID'),
                      const SizedBox(height: 15),

                      _buildTextField(
                        controller: phoneController,
                        icon: Icons.phone_android_outlined,
                        hintText: 'Phone No (03XX-XXXXXXX)',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                          _PhoneNumberFormatter(),
                        ],
                      ),
                      const SizedBox(height: 15),

                      _buildTextField(
                        controller: cnicController,
                        icon: Icons.credit_card_outlined,
                        hintText: 'CNIC (XXXXX-XXXXXXX-X)',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(13),
                          _CNICFormatter(),
                        ],
                      ),
                      const SizedBox(height: 15),

                      // Gender Dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline, color: Color(0xFF00897B)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedGender,
                                  items: ['Male', 'Female']
                                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                                      .toList(),
                                  onChanged: (val) => setState(() => _selectedGender = val!),
                                  hint: const Text('Select Gender'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),

                      _buildTextField(
                          controller: emailController,
                          icon: Icons.email_outlined,
                          hintText: 'Email',
                          keyboardType: TextInputType.emailAddress),
                      const SizedBox(height: 15),

                      _buildTextField(
                          controller: passwordController,
                          icon: Icons.lock_outline,
                          hintText: 'Password',
                          isPassword: true),
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
                          onPressed: _isLoading ? null : _handleNext,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 22, width: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text('Continue',
                                  style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Already have an account
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Already have an account? ',
                              style: TextStyle(color: Colors.black54)),
                          GestureDetector(
                            onTap: () => Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const HamrahLoginPage()),
                              (route) => false,
                            ),
                            child: const Text('Login',
                                style: TextStyle(
                                    color: Color(0xFF00897B),
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
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

  Widget _buildTextField({
    TextEditingController? controller,
    required IconData icon,
    required String hintText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      obscureText: isPassword ? _obscurePassword : false,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF00897B)),
        hintText: hintText,
        suffixIcon: isPassword
            ? IconButton(
          icon: Icon(_obscurePassword
              ? Icons.visibility_off
              : Icons.visibility),
          onPressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        )
            : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.9),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide:
          const BorderSide(color: Color(0xFF00897B), width: 1.5),
        ),
      ),
    );
  }
}

// ── Formatters ──
class _CNICFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text;
    if (text.length > 5 && text[5] != '-')
      text = '${text.substring(0, 5)}-${text.substring(5)}';
    if (text.length > 13 && text[13] != '-')
      text = '${text.substring(0, 13)}-${text.substring(13)}';
    return newValue.copyWith(
        text: text,
        selection: TextSelection.collapsed(offset: text.length));
  }
}

class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text;
    if (text.length > 4 && text[4] != '-')
      text = '${text.substring(0, 4)}-${text.substring(4)}';
    return newValue.copyWith(
        text: text,
        selection: TextSelection.collapsed(offset: text.length));
  }
}