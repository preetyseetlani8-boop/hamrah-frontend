import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/ride_services.dart';
import '../services/auth_service.dart';
import '../services/UserSession.dart';
import '../config/api_config.dart';
import '../widgets/top_right_alert.dart';

class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  String _selectedPeriod = 'This Week';
  final List<String> _periods = ['Today', 'This Week', 'This Month'];

  List<Map<String, dynamic>> _allRides = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRides();
  }

  double _rideEarnings(Map<String, dynamic> ride) {
    final fare =
        double.tryParse('${ride['fare_per_seat'] ?? ride['fare'] ?? 0}') ?? 0;
    final booked =
        int.tryParse('${ride['accepted_count'] ?? 0}') ?? 0;
    return fare * booked;
  }

  DateTime? _rideDate(Map<String, dynamic> ride) {
    final raw = ride['departure_time'] ?? ride['completed_at'];
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString());
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadRides() async {
    setState(() => _loading = true);
    try {
      await AuthService.syncSessionFromMe();
      final rides = await RideService.fetchMyRides();
      if (!mounted) return;
      setState(() {
        _allRides = rides;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      TopRightAlert.show(context,
          title: 'Error', message: e.toString(), isError: true);
    }
  }

  List<Map<String, dynamic>> get _completedRides => _allRides
      .where((ride) => ride['status']?.toString() == 'completed')
      .toList();

  List<Map<String, dynamic>> get _filteredRides {
    final now = DateTime.now();
    return _completedRides.where((ride) {
      final dep = _rideDate(ride);
      if (dep == null) return _selectedPeriod == 'This Month';
      if (_selectedPeriod == 'Today') {
        return dep.year == now.year &&
            dep.month == now.month &&
            dep.day == now.day;
      } else if (_selectedPeriod == 'This Week') {
        final weekStart = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return !dep.isBefore(weekStart);
      } else {
        return dep.year == now.year && dep.month == now.month;
      }
    }).toList();
  }

  double get _totalEarnings =>
      _filteredRides.fold(0.0, (sum, r) => sum + _rideEarnings(r));

  List<double> get _barValues {
    if (_filteredRides.isEmpty) return [0.0];
    if (_selectedPeriod == 'Today') {
      final Map<int, double> hourMap = {};
      for (final r in _filteredRides) {
        final dep = _rideDate(r);
        if (dep == null) continue;
        hourMap[dep.hour] = (hourMap[dep.hour] ?? 0) + _rideEarnings(r);
      }
      if (hourMap.isEmpty) return [0.0];
      final maxVal = hourMap.values.reduce((a, b) => a > b ? a : b);
      if (maxVal == 0) return hourMap.values.map((_) => 0.0).toList();
      return hourMap.values.map((v) => v / maxVal).toList();
    } else if (_selectedPeriod == 'This Week') {
      final Map<int, double> dayMap = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0};
      for (final r in _filteredRides) {
        final dep = _rideDate(r);
        if (dep == null) continue;
        dayMap[dep.weekday] = (dayMap[dep.weekday] ?? 0) + _rideEarnings(r);
      }
      final maxVal = dayMap.values.reduce((a, b) => a > b ? a : b);
      if (maxVal == 0) return dayMap.values.map((_) => 0.1).toList();
      return dayMap.values.map((v) => v == 0 ? 0.1 : v / maxVal).toList();
    } else {
      final Map<int, double> weekMap = {1: 0, 2: 0, 3: 0, 4: 0};
      for (final r in _filteredRides) {
        final dep = _rideDate(r);
        if (dep == null) continue;
        final week = ((dep.day - 1) ~/ 7) + 1;
        weekMap[week.clamp(1, 4)] =
            (weekMap[week.clamp(1, 4)] ?? 0) + _rideEarnings(r);
      }
      final maxVal = weekMap.values.reduce((a, b) => a > b ? a : b);
      if (maxVal == 0) return weekMap.values.map((_) => 0.1).toList();
      return weekMap.values.map((v) => v == 0 ? 0.1 : v / maxVal).toList();
    }
  }

  List<String> get _barLabels {
    if (_selectedPeriod == 'Today') return ['9am', '11am', '2pm', '5pm'];
    if (_selectedPeriod == 'This Week') {
      return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    }
    return ['Wk 1', 'Wk 2', 'Wk 3', 'Wk 4'];
  }

  @override
  Widget build(BuildContext context) {
    final bars = _barValues;
    final labels = _barLabels;
    final total = _totalEarnings;
    final trips = _filteredRides.length;
    final recentRides = _completedRides.take(10).toList();

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
                    const Text('My Earnings',
                        style: TextStyle(
                            color: Color(0xFF00897B),
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF00897B)))
                    : RefreshIndicator(
                        color: const Color(0xFF00897B),
                        onRefresh: _loadRides,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: _periods.map((p) {
                                    final selected = p == _selectedPeriod;
                                    return Expanded(
                                      child: GestureDetector(
                                        onTap: () =>
                                            setState(() => _selectedPeriod = p),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                              milliseconds: 200),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? const Color(0xFF00897B)
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(p,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: selected
                                                      ? Colors.white
                                                      : Colors.grey.shade600)),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00897B),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedPeriod == 'Today'
                                          ? "Today's Earnings"
                                          : _selectedPeriod == 'This Week'
                                              ? 'This Week'
                                              : 'This Month',
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 13),
                                    ),
                                    const SizedBox(height: 6),
                                    Text('Rs. ${total.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 32,
                                            fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        _earningChip(Icons.directions_car_outlined,
                                            '$trips completed trips'),
                                        const SizedBox(width: 10),
                                        _earningChip(Icons.star_outline,
                                            '${UserSession.totalRides} total rides'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 10)
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Earnings Breakdown',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF212121))),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      height: 100,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceAround,
                                        children: List.generate(
                                          bars.length.clamp(0, labels.length),
                                          (i) => Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              AnimatedContainer(
                                                duration: const Duration(
                                                    milliseconds: 400),
                                                width: 28,
                                                height: bars[i] * 80,
                                                decoration: BoxDecoration(
                                                  color: bars[i] >= 0.99
                                                      ? const Color(0xFF00897B)
                                                      : const Color(0xFF00897B)
                                                          .withOpacity(0.35),
                                                  borderRadius:
                                                      const BorderRadius.vertical(
                                                          top: Radius.circular(
                                                              6)),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(labels[i],
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors
                                                          .grey.shade500)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text('Recent Completed Rides',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF212121))),
                              const SizedBox(height: 10),
                              if (recentRides.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'No completed rides yet.\nFinish a ride to see earnings here.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                                )
                              else
                                ...recentRides.map((r) => Container(
                                      margin:
                                          const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 14),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.95),
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.04),
                                              blurRadius: 8)
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor:
                                                const Color(0xFFE0F2F1),
                                            child: const Icon(
                                                Icons.directions_car_outlined,
                                                color: Color(0xFF00897B),
                                                size: 18),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${r['from_address']?.toString().split(',').first ?? '-'} → ${r['to_address']?.toString().split(',').first ?? '-'}',
                                                  style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Color(0xFF212121)),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  _rideDate(r)
                                                          ?.toString()
                                                          .substring(0, 16) ??
                                                      '-',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors
                                                          .grey.shade500),
                                                ),
                                                Text(
                                                  '${r['accepted_count'] ?? 0} passenger(s)',
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors
                                                          .grey.shade600),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            'Rs. ${_rideEarnings(r).toStringAsFixed(0)}',
                                            style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF00897B)),
                                          ),
                                        ],
                                      ),
                                    )),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _earningChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
