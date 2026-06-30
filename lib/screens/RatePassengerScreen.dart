import 'package:flutter/material.dart';
import '../widgets/top_right_alert.dart';
import '../services/UserSession.dart';
import '../services/ride_services.dart';
import 'DriverDashboard.dart';


class RatePassengerScreen extends StatefulWidget {
  final Map<String, dynamic> passenger;
  final String rideId;
  final bool isSinglePassenger;

  final List<Map<String, dynamic>>? remainingPassengers;

  const RatePassengerScreen({
    super.key,
    required this.passenger,
    required this.rideId,
    this.isSinglePassenger = false,
    this.remainingPassengers,
  });

  @override
  State<RatePassengerScreen> createState() => _RatePassengerScreenState();
}

class _RatePassengerScreenState extends State<RatePassengerScreen> {
  int _selectedStars = 0;
  final TextEditingController _commentController = TextEditingController();

  final List<String> _quickTags = [
    'On time',
    'Polite',
    'Clean',
    'Easy pickup',
    'Great communication',
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

    final passengerId = widget.passenger['id']?.toString() ?? '';
    if (passengerId.isNotEmpty) {
      try {
        await RideService.ratePassenger(
          rideId: widget.rideId,
          passengerId: passengerId,
          stars: _selectedStars,
          comment: _commentController.text,
          tags: _selectedTags.toList(),
        );
      } catch (e) {
        debugPrint('Failed to submit rating to backend: $e');
      }
    }

    if (!mounted) return;
    TopRightAlert.show(
      context,
      title: 'Feedback recorded',
      message: 'Thank you for rating your passenger.',
      isError: false,
    );

    // Move to next passenger, or terminate completely if none left
    final hasMore = widget.remainingPassengers != null &&
        widget.remainingPassengers!.isNotEmpty;

    if (hasMore) {
      final nextList = List<Map<String, dynamic>>.from(widget.remainingPassengers!);
      final nextPassenger = nextList.removeAt(0);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RatePassengerScreen(
            passenger: nextPassenger,
            rideId: widget.rideId,
            isSinglePassenger: false,
            remainingPassengers: nextList,
          ),
        ),
      );
    } else {
      // All passengers rated — terminate ride session completely
      UserSession.activeRideId = '';
      await UserSession.save();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DriverDashboardScreen()),
        (route) => false,
      );
    }
  }

  void _skip() async {
    // Skip this rating — move to next or terminate
    final hasMore = widget.remainingPassengers != null &&
        widget.remainingPassengers!.isNotEmpty;

    if (hasMore) {
      final nextList = List<Map<String, dynamic>>.from(widget.remainingPassengers!);
      final nextPassenger = nextList.removeAt(0);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RatePassengerScreen(
            passenger: nextPassenger,
            rideId: widget.rideId,
            isSinglePassenger: false,
            remainingPassengers: nextList,
          ),
        ),
      );
    } else {
      // No more passengers to rate — fully terminate
      UserSession.activeRideId = '';
      await UserSession.save();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DriverDashboardScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final passengerData = widget.passenger;
    final String passengerName = (passengerData['name'] ??
            passengerData['passenger_name'] ??
            passengerData['passengerName'] ??
            'Passenger')
        .toString();
    final String firstName =
        passengerName.isNotEmpty ? passengerName.split(' ').first : 'Passenger';
    final String gender = (passengerData['gender'] ?? 'Unknown').toString();
    final String fare = (passengerData['fare'] ??
            passengerData['price'] ??
            passengerData['amount'] ??
            '---')
        .toString();
    final String seats = (passengerData['seats'] ?? 1).toString();

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
                const Icon(Icons.star_rate_rounded,
                    size: 60, color: Color(0xFF00897B)),
                const SizedBox(height: 12),
                const Text(
                  'Rate your passenger',
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
                              passengerName,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF212121)),
                            ),
                            Text(
                              '$seats seat${seats == '1' ? '' : 's'}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        fare.startsWith('Rs.') ? fare : 'Rs. $fare',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF00897B)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
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
                TextButton(
                  onPressed: _skip,
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
