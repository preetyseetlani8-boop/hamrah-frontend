// lib/screens/splash_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// REDESIGNED: Cinematic splash with:
//   • Animated road/path that draws itself across the screen
//   • Car icon that travels along the road
//   • Staggered text reveal (app name + tagline)
//   • Pulsing dot trail instead of generic spinner
//   • Smooth fade-out transition to login
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'Ridebook.dart';
import 'offerride.dart';
import 'DriverDashboard.dart';
import '../services/UserSession.dart';
import '../services/auth_service.dart';
import '../services/ride_services.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  // ── Controllers ─────────────────────────────────────────────────────────────
  late AnimationController _roadController;      // road drawing
  late AnimationController _carController;       // car travel
  late AnimationController _textController;      // text stagger
  late AnimationController _dotsController;      // pulsing dots
  late AnimationController _fadeController;      // final fade-out
  late AnimationController _logoController;      // logo pop-in

  // ── Animations ──────────────────────────────────────────────────────────────
  late Animation<double> _roadProgress;
  late Animation<double> _carProgress;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _titleOpacity;
  late Animation<Offset> _titleSlide;
  late Animation<double> _taglineOpacity;
  late Animation<Offset> _taglineSlide;
  late Animation<double> _screenFade;

  @override
  void initState() {
    super.initState();
    print('DEBUG: initState called');
    // Road draws in 1.2s
    _roadController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _roadProgress = CurvedAnimation(
      parent: _roadController,
      curve: Curves.easeInOut,
    );

    // Car travels in 1.4s (starts slightly after road)
    _carController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _carProgress = CurvedAnimation(
      parent: _carController,
      curve: Curves.easeInOut,
    );

    // Logo pops in at 0.6s
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController,
          curve: const Interval(0.0, 0.4, curve: Curves.easeIn)),
    );

    // Text stagger: title then tagline
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    ));
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
      ),
    );
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
    ));

    // Pulsing dots loop
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Final screen fade
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _screenFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    // 1. Road draws
    await _roadController.forward();
    // 2. Car travels + logo pops in simultaneously
    _carController.forward();
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    // 3. Text reveals
    await _textController.forward();
    // 4. Dots start pulsing
    _dotsController.repeat();
    // 5. Hold, then resolve next screen before fade-out
    await Future.delayed(const Duration(milliseconds: 1200));
    print('DEBUG: about to navigate, token is: ${UserSession.token}');
    final home = await _resolveHomeScreen();
    if (!mounted) return;
    await _fadeController.forward();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => home,
        transitionDuration: Duration.zero,
      ),
    );
  }

  Future<Widget> _resolveHomeScreen() async {
    if (UserSession.token.isEmpty) {
      return const HamrahLoginPage();
    }

    try {
      final me = await AuthService.fetchMe()
          .timeout(const Duration(seconds: 8));
      UserSession.name      = '${me['first_name'] ?? ''} ${me['last_name'] ?? ''}'.trim();
      UserSession.studentId = me['dsu_reg_id']?.toString() ?? '';
      UserSession.phone     = me['phone_number']?.toString() ?? '';
      UserSession.email     = me['email']?.toString() ?? '';
      UserSession.registeredRoles = [];
      if (me['is_passenger'] == true) UserSession.registeredRoles.add('passenger');
      if (me['is_driver']    == true) UserSession.registeredRoles.add('driver');
      UserSession.totalRides = me['total_rides'] as int? ?? 0;
      UserSession.activeRole = me['active_mode']?.toString() ?? UserSession.activeRole;
      final vehicles = me['vehicles'] as List?;
      if (vehicles != null && vehicles.isNotEmpty) {
        final car = vehicles.firstWhere(
          (v) => v['mode_of_transport'] == 'car', orElse: () => vehicles[0]);
        UserSession.vehicleId     = car['id'] as int? ?? 0;
        UserSession.vehicleMode   = car['mode_of_transport']?.toString() ?? '';
        UserSession.vehicleNumber = car['vehicle_number']?.toString() ?? '';
        UserSession.vehicleModel  = car['vehicle_model']?.toString() ?? '';
        UserSession.vehicleColour = car['vehicle_colour']?.toString() ?? '';
      }
    } catch (_) {}

    if (UserSession.activeRole == 'driver') {
      try {
        final list = await RideService.fetchMyRides()
            .timeout(const Duration(seconds: 8));
        final ongoing = list.any((r) =>
            r['status'] == 'ongoing' ||
            (r['status'] == 'active' && (r['accepted_count'] ?? 0) > 0));
        return ongoing ? const DriverDashboardScreen() : const OfferRidePage();
      } catch (_) {
        return const OfferRidePage();
      }
    }

    return const RideSearchScreen();
  }

  @override
  void dispose() {
    _roadController.dispose();
    _carController.dispose();
    _textController.dispose();
    _dotsController.dispose();
    _fadeController.dispose();
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: _screenFade,
      builder: (context, child) {
        return Opacity(
          opacity: _screenFade.value,
          child: child,
        );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF00695C), // deep teal
        body: Stack(
          children: [
            // ── Background geometric pattern ──────────────────────────────
            Positioned.fill(
              child: CustomPaint(
                painter: _BackgroundPatternPainter(),
              ),
            ),

            // ── Animated road ────────────────────────────────────────────
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _roadProgress,
                builder: (context, _) => CustomPaint(
                  painter: _RoadPainter(progress: _roadProgress.value),
                ),
              ),
            ),

            // ── Animated car on road ──────────────────────────────────────
            AnimatedBuilder(
              animation: _carProgress,
              builder: (context, _) {
                final t = _carProgress.value;
                // Road path: from left edge, curves upward, to right edge
                // matches _RoadPainter path
                final x = _roadX(t, size.width);
                final y = _roadY(t, size.height);
                return Positioned(
                  left: x - 14,
                  top: y - 10,
                  child: Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Container(
                      width: 28,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.directions_car_filled_rounded,
                          size: 14,
                          color: Color(0xFF00897B),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // ── Center content ────────────────────────────────────────────
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo circle
                  AnimatedBuilder(
                    animation: _logoController,
                    builder: (context, _) => Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Image.asset(
                              'assets/logo.png',
                              width: 56,
                              height: 56,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.directions_car_filled_rounded,
                                size: 48,
                                color: Color(0xFF00897B),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // App name
                  AnimatedBuilder(
                    animation: _textController,
                    builder: (context, _) => FadeTransition(
                      opacity: _titleOpacity,
                      child: SlideTransition(
                        position: _titleSlide,
                        child: const Text(
                          'Hamrah',
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 2,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Tagline
                  AnimatedBuilder(
                    animation: _textController,
                    builder: (context, _) => FadeTransition(
                      opacity: _taglineOpacity,
                      child: SlideTransition(
                        position: _taglineSlide,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.3)),
                          ),
                          child: const Text(
                            'Campus carpooling',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 52),

                  // Pulsing dot trail loader
                  AnimatedBuilder(
                    animation: _dotsController,
                    builder: (context, _) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(4, (i) {
                          final phase =
                          (_dotsController.value - i * 0.2).clamp(0.0, 1.0);
                          final pulse = math.sin(phase * math.pi).clamp(0.0, 1.0);
                          return Padding(
                            padding:
                            const EdgeInsets.symmetric(horizontal: 5),
                            child: Transform.scale(
                              scale: 0.6 + pulse * 0.6,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white
                                      .withOpacity(0.4 + pulse * 0.6),
                                ),
                              ),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ],
              ),
            ),

            // ── Bottom tagline strip ──────────────────────────────────────
            Positioned(
              bottom: 36,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _taglineOpacity,
                builder: (context, _) => Opacity(
                  opacity: _taglineOpacity.value,
                  child: const Text(
                    'Powered by DSU',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Road curve math (matches _RoadPainter) ─────────────────────────────────
  double _roadX(double t, double screenWidth) {
    // Cubic bezier: left→curve up→right
    const x0 = 0.0, x1 = 0.3, x2 = 0.7, x3 = 1.0;
    final mt = 1 - t;
    return screenWidth *
        (mt * mt * mt * x0 +
            3 * mt * mt * t * x1 +
            3 * mt * t * t * x2 +
            t * t * t * x3);
  }

  double _roadY(double t, double screenHeight) {
    final cy1 = screenHeight * 0.7;
    final cy2 = screenHeight * 0.3;
    final mt = 1 - t;
    return mt * mt * mt * (screenHeight * 0.72) +
        3 * mt * mt * t * cy1 +
        3 * mt * t * t * cy2 +
        t * t * t * (screenHeight * 0.28);
  }
}

// ── Road painter ────────────────────────────────────────────────────────────
class _RoadPainter extends CustomPainter {
  final double progress;
  _RoadPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final roadPaint = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..strokeCap = StrokeCap.round;

    final dashedPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Full road path
    final fullPath = Path()
      ..moveTo(0, size.height * 0.72)
      ..cubicTo(
        size.width * 0.3, size.height * 0.7,
        size.width * 0.7, size.height * 0.3,
        size.width, size.height * 0.28,
      );

    // Draw only up to progress
    final metrics = fullPath.computeMetrics().first;
    final partial = metrics.extractPath(0, metrics.length * progress);

    canvas.drawPath(partial, roadPaint);

    // Dashed center line
    final dashPath = _buildDashedPath(partial, metrics.length * progress);
    canvas.drawPath(dashPath, dashedPaint);
  }

  Path _buildDashedPath(Path source, double totalLen) {
    final result = Path();
    if (totalLen <= 0) return result;

    final metric = source.computeMetrics().first;
    double dist = 0;
    const dashLen = 12.0;
    const gapLen = 8.0;
    bool drawing = true;

    while (dist < totalLen) {
      final seg = drawing ? dashLen : gapLen;
      final end = (dist + seg).clamp(0.0, totalLen);

      if (drawing && end > dist) {
        // Use getTangentForOffset to get points and draw manually
        final startTangent = metric.getTangentForOffset(dist);
        final endTangent = metric.getTangentForOffset(end);

        if (startTangent != null && endTangent != null) {
          result.moveTo(startTangent.position.dx, startTangent.position.dy);
          result.lineTo(endTangent.position.dx, endTangent.position.dy);
        }
      }

      dist += seg;
      drawing = !drawing;
    }

    return result;
  }

  @override
  bool shouldRepaint(_RoadPainter old) => old.progress != progress;
}

// ── Background geometric pattern ────────────────────────────────────────────
class _BackgroundPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Diagonal grid
    const spacing = 40.0;
    for (double x = -size.height; x < size.width + size.height; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
    }

    // Subtle circle accents
    final circlePaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawCircle(
        Offset(size.width * 0.1, size.height * 0.15), 80, circlePaint);
    canvas.drawCircle(
        Offset(size.width * 0.9, size.height * 0.85), 120, circlePaint);
    canvas.drawCircle(
        Offset(size.width * 0.85, size.height * 0.1), 50, circlePaint);
  }

  @override
  bool shouldRepaint(_BackgroundPatternPainter _) => false;
}