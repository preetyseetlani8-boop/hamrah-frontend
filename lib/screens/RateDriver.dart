// lib/screens/rate_driver_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../widgets/top_right_alert.dart';
import '../services/ride_services.dart';
import '../services/UserSession.dart';
import '../config/api_config.dart';
import 'Ridebook.dart';

class RateDriverScreen extends StatefulWidget {
  final Map<String, dynamic> driver;
  final List<Map<String, dynamic>>? remainingUnrated;

  const RateDriverScreen({
    super.key,
    required this.driver,
    this.remainingUnrated,
  });

  @override
  State<RateDriverScreen> createState() => _RateDriverScreenState();
}

class _RateDriverScreenState extends State<RateDriverScreen> {
  int _selectedStars = 0;
  final TextEditingController _commentController = TextEditingController();

  final List<String> _quickTags = [
    'Great driver',
    'On time',
    'Clean car',
    'Safe driving',
    'Friendly',
  ];
  final Set<String> _selectedTags = {};

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    if (_selectedStars == 0) {
      TopRightAlert.show(
        context,
        title: 'Rating Required',
        message: 'Select a star rating.',
        isError: true,
      );
      return;
    }

    try {
      // Defensively parse ride ID from all common naming variants
      final rideId = UserSession.activeRideId.isNotEmpty
          ? UserSession.activeRideId
          : (widget.driver['ride_id'] ?? widget.driver['id'] ?? '').toString();

      if (rideId.isNotEmpty) {
        UserSession.activeRideId = rideId;
        await RideService.rateRide(
          rideId: rideId,
          stars: _selectedStars,
          comment: _commentController.text.trim(),
          tags: _selectedTags.toList(),
        );
      } else {
        print("[Rating System] Warning: Attempted to submit rating but no valid ride ID was found.");
      }

      if (!mounted) return;
      TopRightAlert.show(
        context,
        title: 'Rating submitted',
        message: 'Thank you for your feedback.',
        isError: false,
      );

      UserSession.activeRideId = '';

      // SAFETY: Re-fetch remaining unrated rides from backend
      // This prevents getting stuck if the cached list is stale or contains
      // already-rated rides (e.g., due to rating errors or duplicate requests)
      final remainingFromBackend = await _fetchRemainingUnrated();

      if (remainingFromBackend.isNotEmpty && mounted) {
        // Show next unrated ride (use backend's fresh list)
        final nextRide = remainingFromBackend.first;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RateDriverScreen(
              driver: {
                'name': nextRide['driver_name'] ?? 'Driver',
                'ride_id': nextRide['ride_id'],
                'vehicle': 'Car',
                'plate': nextRide['vehicle_number'] ?? '',
                'price': 'Rs. ${nextRide['fare'] ?? 0}',
                'from': nextRide['from_address'] ?? '',
                'to': nextRide['to_address'] ?? '',
              },
              remainingUnrated: remainingFromBackend.sublist(1),
            ),
          ),
        );
      } else {
        // No more unrated rides, go to main screen
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const RideSearchScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      TopRightAlert.show(
        context,
        title: 'Rating Failed',
        message: e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  /// Fetch remaining unrated rides from backend (with safety cap)
  Future<List<Map<String, dynamic>>> _fetchRemainingUnrated() async {
    try {
      final response = await http.get(
        ApiConfig.uri('/ratings/unrated'),
        headers: ApiConfig.jsonHeaders(),
      );
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List;
        // SAFETY: Cap at 50 to prevent infinite loops in case of bugs
        final capped = list.take(50).toList();
        return capped.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Show confirmation dialog before skipping rating
  Future<void> _showSkipDialog() async {
    final hasMore = (widget.remainingUnrated?.isNotEmpty ?? false);
    final message = hasMore
        ? 'You have more unrated rides. Skip this and the remaining ones?'
        : 'Skip rating this ride?';

    final shouldSkip = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skip Rating?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Skip', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldSkip == true && mounted) {
      // Skip to main screen (don't loop through remaining)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const RideSearchScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final driverData = widget.driver;

    // ── Defensively Extract Map Strings to Guarantee Non-Null Values ─────────
    final String driverName = (driverData['name'] ?? driverData['driver_name'] ?? 'Your Driver').toString();
    final String firstName  = driverName.isNotEmpty ? driverName.split(' ').first : 'Driver';
    final String gender     = (driverData['gender'] ?? driverData['driver_gender'] ?? 'Unknown').toString();
    final String vehicle    = (driverData['vehicle'] ?? driverData['vehicle_info'] ?? driverData['vehicle_details'] ?? 'Standard Ride').toString();
    final String price      = (driverData['price'] ?? driverData['fare'] ?? driverData['amount'] ?? '---').toString();

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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              children: [
                // Header
                const Icon(Icons.star_rate_rounded,
                    size: 60, color: Color(0xFF00897B)),
                const SizedBox(height: 12),
                const Text(
                  'Rate your ride',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00897B)),
                ),
                const SizedBox(height: 6),
                Text(
                  'How was your ride with $firstName?',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),

                // Driver card (compact)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: const Color(0xFFE0F2F1),
                        child: Icon(
                          gender == 'Female' ? Icons.face_3 : Icons.face,
                          color: const Color(0xFF00897B),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driverName,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF212121)),
                            ),
                            Text(
                              vehicle,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        price,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF00897B)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // Stars
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final filled = i < _selectedStars;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedStars = i + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          filled
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: filled ? Colors.amber : Colors.grey.shade400,
                          size: 44,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedStars == 0
                      ? 'Tap to rate'
                      : ['', 'Poor', 'Fair', 'Good', 'Great', 'Excellent']
                          [_selectedStars],
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _selectedStars > 0
                          ? Colors.amber.shade700
                          : Colors.grey),
                ),
                const SizedBox(height: 24),

                // Quick tags
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: _quickTags.map((tag) {
                    final selected = _selectedTags.contains(tag);
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selected
                              ? _selectedTags.remove(tag)
                              : _selectedTags.add(tag);
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF00897B)
                              : Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF00897B)
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? Colors.white
                                : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Comment box
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Add a comment (optional)',
                    hintStyle:
                        TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.9),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                          color: Color(0xFF00897B), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // Submit
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _submitRating,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00897B),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                      elevation: 0,
                    ),
                    child: const Text('Submit rating',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                ),

                // Skip (with confirmation to prevent accidental skips)
                TextButton(
                  onPressed: _showSkipDialog,
                  child: const Text('Skip',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}