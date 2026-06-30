// lib/screens/forgot_password_screen.dart
import 'dart:async'; // Added for Timer
import 'package:flutter/material.dart';
import '../widgets/top_right_alert.dart';
import '../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;
  bool _codeSent = false;

  final List<TextEditingController> _otpControllers =
  List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
  List.generate(6, (_) => FocusNode());

  final TextEditingController _newPassController = TextEditingController();
  final TextEditingController _confirmPassController =
  TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _otpVerified = false;

  // Timer properties
  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel(); // Cancel timer on dispose
    _emailController.dispose();
    for (final c in _otpControllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    _newPassController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  // Starts the 3-minute countdown clock
  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  // Formats raw seconds into an MM:SS layout
  String get _formattedTimer {
    final minutes = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _sendCode() async {
    if (_secondsLeft > 0 || _isLoading) return; // Prevent spamming while timer runs

    if (_emailController.text.isEmpty ||
        !_emailController.text.contains('@')) {
      TopRightAlert.show(context,
          title: 'Invalid Email',
          message: 'Enter a valid email address.',
          isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await AuthService.forgotPassword(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _codeSent = true;
      });
      _startTimer(); // Kick off the countdown on success
      TopRightAlert.show(context,
          title: 'Code Sent',
          message: 'A reset code has been sent to ${_emailController.text}.',
          isError: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      TopRightAlert.show(context,
          title: 'Error',
          message: e.toString().replaceFirst('Exception: ', ''),
          isError: true);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length < 6) {
      TopRightAlert.show(context,
          title: 'Incomplete Code',
          message: 'Enter the 6-digit code.',
          isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await AuthService.verifyForgotPasswordOtp(
        email: _emailController.text.trim(),
        otp: otp,
      );
      if (!mounted) return;
      _timer?.cancel(); // Clear the timer once successfully verified
      setState(() { _isLoading = false; _otpVerified = true; });
      TopRightAlert.show(context,
          title: 'Code Verified',
          message: 'Set a new password.',
          isError: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      TopRightAlert.show(context,
          title: 'Invalid Code',
          message: e.toString().replaceFirst('Exception: ', ''),
          isError: true);
    }
  }

  Future<void> _resetPassword() async {
    if (_newPassController.text.length < 6) {
      TopRightAlert.show(context,
          title: 'Weak Password',
          message: 'Password must be at least 6 characters.',
          isError: true);
      return;
    }
    if (_newPassController.text != _confirmPassController.text) {
      TopRightAlert.show(context,
          title: 'Mismatch',
          message: 'Passwords do not match.',
          isError: true);
      return;
    }

    final otp = _otpControllers.map((c) => c.text).join();
    setState(() => _isLoading = true);

    try {
      await AuthService.resetPassword(
        email: _emailController.text.trim(),
        otp: otp,
        newPassword: _newPassController.text.trim(),
      );
      if (!mounted) return;
      TopRightAlert.show(context,
          title: 'Password updated',
          message: 'Sign in with your new password.',
          isError: false);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      TopRightAlert.show(context,
          title: 'Reset Failed',
          message: e.toString().replaceFirst('Exception: ', ''),
          isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _secondsLeft == 0 && !_isLoading;

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
          child: SingleChildScrollView(
            padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new,
                      color: Color(0xFF00897B)),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(height: 10),

                const Icon(Icons.lock_reset_outlined,
                    size: 60, color: Color(0xFF00897B)),
                const SizedBox(height: 16),
                const Text('Forgot Password?',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00897B))),
                const SizedBox(height: 8),
                Text(
                  _otpVerified
                      ? 'Set your new password below.'
                      : _codeSent
                      ? 'Enter the 6-digit code sent to your email.'
                      : 'Enter your registered email and we\'ll send you a reset code.',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 30),

                // ── Step 1: Email ──────────────────────────────────────
                if (!_codeSent && !_otpVerified) ...[
                  _buildTextField(
                    controller: _emailController,
                    icon: Icons.email_outlined,
                    label: 'Registered Email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _sendCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(
                          color: Colors.white)
                          : const Text('Send code',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ),
                ],

                // ── Step 2: OTP ────────────────────────────────────────
                if (_codeSent && !_otpVerified) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(6, (i) => _otpBox(i)),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _verifyOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Verify code',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: canResend ? _sendCode : null,
                      child: Text(
                        _secondsLeft > 0
                            ? 'Resend Code in $_formattedTimer'
                            : 'Resend Code',
                        style: TextStyle(
                            color: canResend ? const Color(0xFF00897B) : Colors.grey,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],

                // ── Step 3: New password ────────────────────────────────
                if (_otpVerified) ...[
                  _buildTextField(
                    controller: _newPassController,
                    icon: Icons.lock_outline,
                    label: 'New Password',
                    isPassword: true,
                    obscure: _obscureNew,
                    onToggle: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                  const SizedBox(height: 14),
                  _buildTextField(
                    controller: _confirmPassController,
                    icon: Icons.lock_outline,
                    label: 'Confirm Password',
                    isPassword: true,
                    obscure: _obscureConfirm,
                    onToggle: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _resetPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                        elevation: 0,
                      ),
                      child: const Text('Update password',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _otpBox(int index) {
    return SizedBox(
      width: 45,
      child: TextField(
        controller: _otpControllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(
            fontSize: 22, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Colors.white.withOpacity(0.9),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.grey)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                  color: Color(0xFF00897B), width: 2)),
        ),
        onChanged: (v) {
          if (v.isNotEmpty && index < 5) {
            _focusNodes[index + 1].requestFocus();
          } else if (v.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
        },
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    TextInputType? keyboardType,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onToggle,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF00897B)),
        suffixIcon: isPassword
            ? IconButton(
            icon: Icon(
                obscure ? Icons.visibility_off : Icons.visibility),
            onPressed: onToggle)
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