import 'dart:async';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import '../widgets/top_right_alert.dart';
import '../services/UserSession.dart';
import '../services/auth_service.dart';
import '../services/registration_service.dart';

class OtpVerificationPage extends StatefulWidget {
  final String registrationRole;

  const OtpVerificationPage({
    super.key,
    this.registrationRole = 'driver',
  });

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isVerifying = false;
  bool _isResending = false;

  // 180 seconds = 3 minutes countdown clock
  int _secondsLeft = 180;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  // Robust countdown loop configuration
  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 180);
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

  // Helper utility to format raw seconds into an MM:SS digital clock layout
  String get _formattedTimer {
    final minutes = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _resendOtp() async {
    if (_secondsLeft > 0 || _isResending) return;
    final email = UserSession.email.trim();
    if (email.isEmpty) {
      TopRightAlert.show(context,
          title: 'Email Missing',
          message: 'No email found for resend.',
          isError: true);
      return;
    }

    setState(() => _isResending = true);
    try {
      await AuthService.resendOtp(email: email, role: widget.registrationRole);
      if (!mounted) return;
      TopRightAlert.show(context,
          title: 'OTP Sent',
          message: 'A new code was sent to $email',
          isError: false);
      _startTimer();
    } catch (e) {
      if (!mounted) return;
      TopRightAlert.show(context,
          title: 'Resend Failed',
          message: e.toString().replaceFirst('Exception: ', ''),
          isError: true);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _controllers.map((c) => c.text).join();

    if (otp.length != 6) {
      TopRightAlert.show(
        context,
        title: 'Invalid OTP',
        message: 'Enter the 6-digit code.',
        isError: true,
      );
      return;
    }

    setState(() => _isVerifying = true);

    try {
      final result = await AuthService.verifyOtp(
        email: UserSession.email,
        otp: otp,
        role: widget.registrationRole,
      );

      if (!mounted) return;

      RegistrationService.clearDraft();

      TopRightAlert.show(
        context,
        title: 'Verified',
        message: result['message']?.toString() ?? 'Registration complete. Please login.',
        isError: false,
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HamrahLoginPage()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      TopRightAlert.show(
        context,
        title: 'Verification Failed',
        message: e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = UserSession.email.trim();
    final canResend = _secondsLeft == 0 && !_isResending;

    return Scaffold(
      resizeToAvoidBottomInset: true,
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.mark_email_read_outlined,
                    size: 80,
                    color: Color(0xFF00897B),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Verification code',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00897B),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    email.isNotEmpty
                        ? 'Enter the code sent to $email'
                        : 'Enter the code sent to your email',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(6, (index) {
                      return SizedBox(
                        width: 45,
                        child: TextField(
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          maxLength: 1,
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onChanged: (value) {
                            if (value.isNotEmpty && index < 5) {
                              _focusNodes[index + 1].requestFocus();
                            } else if (value.isEmpty && index > 0) {
                              _focusNodes[index - 1].requestFocus();
                            }
                          },
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isVerifying ? null : _verifyOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Verify code',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: canResend ? _resendOtp : null,
                    child: _isResending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _secondsLeft > 0
                                ? 'Resend OTP in $_formattedTimer'
                                : 'Resend OTP',
                            style: TextStyle(
                              color: canResend
                                  ? const Color(0xFF00897B)
                                  : Colors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}