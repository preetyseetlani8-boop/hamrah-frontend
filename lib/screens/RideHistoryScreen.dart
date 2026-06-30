// lib/screens/ride_history_screen.dart
import 'package:flutter/material.dart';
import '../services/ride_services.dart';
import '../services/UserSession.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  List<Map<String, dynamic>> _rides = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // Calculates earning from raw ride data
  double _calcEarning(Map<String, dynamic> r) {
    final fare = _toDouble(r['fare_per_seat'] ?? r['fare'] ?? 0);
    final booked = int.tryParse('${r['accepted_count'] ?? r['booked_seats'] ?? 0}') ?? 0;
    return fare * booked;
  }

  // Robust number parser that handles strings like "Rs. 150" and numbers
  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll(RegExp(r'[^0-9]'), '');
    return double.tryParse(s) ?? 0;
  }

  Future<void> _loadHistory() async {
    try {
      List<Map<String, dynamic>> rides;

      if (UserSession.isDriver && UserSession.activeRole == 'driver') {
        final raw = await RideService.fetchMyRides();
        rides = raw.map((r) {
          String date = '', time = '';
          try {
            final dt = DateTime.parse(r['departure_time'].toString());
            date = '${dt.day} ${_month(dt.month)}, ${dt.year}';
            time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          } catch (_) {}

          final earning = _calcEarning(r);

          return {
            'raw':         r,                          // keep raw for earning recalc
            'driver':      UserSession.name,
            'vehicle':     UserSession.vehicleNumber,
            'pickup':      r['from_address'] ?? '',
            'destination': r['to_address'] ?? '',
            'date':        date,
            'time':        time,
            'earning':     earning,                    // numeric, not string
            'fare':        'Rs. ${earning.toStringAsFixed(0)}',
            'rating':      0,
            'status':      _statusLabel(r['status']?.toString() ?? 'active'),
          };
        }).toList();
      } else {
        rides = await RideService.fetchRideHistory();
        // Normalize passenger rides to also have numeric 'earning' and proper status
        rides = rides.map((r) {
          // Use _toDouble helper which handles both numeric and "Rs. 150" string
          final earning = _toDouble(r['fare'] ?? r['fare_per_seat'] ?? 0);
          // Normalize status to title case for consistent comparison
          String normalizedStatus = (r['status'] ?? '').toString();
          if (normalizedStatus.toLowerCase() == 'completed') {
            normalizedStatus = 'Completed';
          }
          return {...r, 'earning': earning, 'status': normalizedStatus};
        }).toList();
      }

      if (!mounted) return;
      setState(() {
        _rides = rides;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _month(int m) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[m - 1];
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      case 'active':    return 'Active';
      default:          return s;
    }
  }

  // Total spent (passenger) / Total earned (driver) — only completed rides
  double get _totalEarned => _rides.fold(0.0, (sum, r) {
    final status = r['status']?.toString().toLowerCase() ?? '';
    final rawStatus = r['raw_status']?.toString().toLowerCase() ?? '';
    // A ride counts as completed if:
    // - status is "Completed" / "completed"
    // - OR raw_status is "completed"/"dropped"/"rated"/"finished"
    final isCompleted = status == 'completed' ||
        rawStatus == 'completed' ||
        rawStatus == 'dropped' ||
        rawStatus == 'rated' ||
        rawStatus == 'finished';
    if (!isCompleted) return sum;
    return sum + ((r['earning'] as num?)?.toDouble() ?? 0.0);
  });

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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF00897B)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text(
                      'Ride History',
                      style: TextStyle(
                          color: Color(0xFF00897B),
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              // Stats row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _statCard('Total Rides', '${_rides.length}', Icons.directions_car_outlined),
                    const SizedBox(width: 12),
                    _statCard(
                      UserSession.isDriver ? 'Total Earned' : 'Total Spent',
                      'Rs. ${_totalEarned.toStringAsFixed(0)}',   // ← fixed
                      Icons.payments_outlined,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00897B)))
                    : _rides.isEmpty
                        ? const Center(child: Text('No rides yet.', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _rides.length,
                            itemBuilder: (context, index) => _rideCard(_rides[index]),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFE0F2F1),
              child: Icon(icon, color: const Color(0xFF00897B), size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF212121))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rideCard(Map<String, dynamic> ride) {
    final isCompleted = ride['status'] == 'Completed';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFE0F2F1),
                child: const Icon(Icons.face, color: Color(0xFF00897B), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ride['driver'] ?? '',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF212121))),
                    Text(ride['vehicle'] ?? '',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(ride['fare_display'] ?? ride['fare']?.toString() ?? 'Rs. 0',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF00897B))),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? const Color(0xFF00897B).withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      ride['status'] ?? '',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isCompleted ? const Color(0xFF00897B) : Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 12),
          Row(
            children: [
              Column(
                children: [
                  const Icon(Icons.my_location, size: 12, color: Color(0xFF00897B)),
                  Container(width: 1, height: 16, color: Colors.grey.shade300),
                  const Icon(Icons.location_on, size: 12, color: Colors.redAccent),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ride['pickup'] ?? '',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF212121))),
                    const SizedBox(height: 10),
                    Text(ride['destination'] ?? '',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF212121))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(ride['date'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  const SizedBox(height: 4),
                  Text(ride['time'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  if (isCompleted && (ride['rating'] ?? 0) > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        ride['rating'] as int,
                        (_) => const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}