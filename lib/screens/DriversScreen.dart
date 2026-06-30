import 'package:finalyearproject/screens/RideConfirmation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../widgets/top_right_alert.dart';
import '../services/ride_services.dart';
import '../services/UserSession.dart';

class AvailableDriversScreen extends StatefulWidget {
  final String pickup;
  final String destination;
  final String vehicleType;
  final int seats;
  final String gender;
  final double? pickupLat;
  final double? pickupLng;
  final double? destLat;
  final double? destLng;
  final bool isAC;
  final DateTime? targetTime;

  const AvailableDriversScreen({
    super.key,
    required this.pickup,
    required this.destination,
    required this.vehicleType,
    required this.seats,
    required this.gender,
    this.pickupLat,
    this.pickupLng,
    this.destLat,
    this.destLng,
    this.isAC = false,
    this.targetTime,
  });

  @override
  State<AvailableDriversScreen> createState() => _AvailableDriversScreenState();
}

class _AvailableDriversScreenState extends State<AvailableDriversScreen> {
  int? selectedDriver;
  final List<Map<String, dynamic>> visibleDrivers = [];
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  bool _isLoading = true;
  bool _isBooking = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _allDrivers = [];

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  Future<void> _loadDrivers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final drivers = await RideService.searchDrivers(
        pickup: widget.pickup,
        destination: widget.destination,
        vehicleType: widget.vehicleType,
        seats: widget.seats,
        gender: widget.gender,
        pickupLat: widget.pickupLat,
        pickupLng: widget.pickupLng,
        destLat: widget.destLat,
        destLng: widget.destLng,
        isAC: widget.isAC,
        targetTime: widget.targetTime,
      );

      if (!mounted) return;
      setState(() {
        _allDrivers = drivers;
        visibleDrivers.addAll(drivers);
        _isLoading = false;
      });
      // _insertDriversOneByOne(); // animation disabled for reliability
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _insertDriversOneByOne() {
    visibleDrivers.clear();
    final list = _allDrivers;
    for (int i = 0; i < list.length; i++) {
      Future.delayed(Duration(milliseconds: 300 + i * 400), () {
        if (!mounted) return;
        visibleDrivers.add(list[i]);
        _listKey.currentState?.insertItem(
          visibleDrivers.length - 1,
          duration: const Duration(milliseconds: 350),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFE0F2F1), Color(0xFFF5F7F9)],
                ),
              ),
            ),
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Color(0xFF00897B)))
          else if (_errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadDrivers,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                      ),
                      child: const Text('Retry', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            )
          else
            _buildDriverList(),
        ],
      ),
    );
  }

  Widget _buildDriverList() {
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF00897B)),
                  onPressed: () => Navigator.pop(context),
                ),
                const Expanded(
                  child: Text(
                    'Available rides',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00897B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00897B)))
              : visibleDrivers.isEmpty
              ? _emptyState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  itemCount: visibleDrivers.length,
                  itemBuilder: (context, index) =>
                      _driverCard(visibleDrivers[index], index),
                ),
        ),
        if (visibleDrivers.isNotEmpty)
          _bottomBar(),
      ],
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: selectedDriver == null || _isBooking ? null : _bookRide,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00897B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _isBooking
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text(
                  'Book ride',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
        ),
      ),
    );
  }

  Widget _driverCard(Map<String, dynamic> driver, int index) {
    final isSelected = selectedDriver == index;
    return GestureDetector(
      onTap: () => setState(() => selectedDriver = index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF00897B) : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Driver info row
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFE0F2F1),
                  child: Text(
                    (driver['name'] as String? ?? 'D').isNotEmpty
                        ? (driver['name'] as String).substring(0, 1)
                        : 'D',
                    style: const TextStyle(
                        color: Color(0xFF00897B), fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(driver['name'] ?? 'Driver',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('★ ${driver['rating']}  •  ${driver['trips']} trips',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Text(driver['price'].toString(),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF00897B))),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Route info
            Row(children: [
              const Icon(Icons.my_location, size: 14, color: Color(0xFF00897B)),
              const SizedBox(width: 6),
              Expanded(child: Text(
                driver['from']?.toString().split(',').first ?? '-',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              )),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on, size: 14, color: Colors.redAccent),
              const SizedBox(width: 6),
              Expanded(child: Text(
                driver['to']?.toString().split(',').first ?? '-',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              )),
            ]),
            const SizedBox(height: 8),

            // Extra pickup points
            if ((driver['pickup_points'] as List?)?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00897B).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF00897B).withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📍 Also picks up from:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            color: Color(0xFF00897B))),
                    const SizedBox(height: 4),
                    ...(driver['pickup_points'] as List).map((pp) =>
                      Text('• ${pp['address']?.toString().split(',').first ?? ''}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],

            // Time + vehicle + seats
            Row(children: [
              const Icon(Icons.access_time, size: 13, color: Colors.grey),
              const SizedBox(width: 4),
              Text(driver['eta']?.toString() ?? '--',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(width: 12),
              const Icon(Icons.directions_car_outlined, size: 13, color: Colors.grey),
              const SizedBox(width: 4),
              Text(driver['vehicle']?.toString() ?? '',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(width: 12),
              const Icon(Icons.event_seat, size: 13, color: Colors.grey),
              const SizedBox(width: 4),
              Text('${driver['seats'] ?? 1} seats',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              if (driver['ac'] == true) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('AC', style: TextStyle(fontSize: 10,
                      color: Colors.blue, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text('No drivers found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Future<void> _bookRide() async {
    if (selectedDriver == null) return;
    final driver = visibleDrivers[selectedDriver!];
    final rideId = driver['ride_id']?.toString() ?? driver['id']?.toString() ?? '';

    if (rideId.isEmpty) {
      TopRightAlert.show(context,
          title: 'Error', message: 'Invalid ride id from server.', isError: true);
      return;
    }

    setState(() => _isBooking = true);

    try {
      final result = await RideService.bookRide(
        rideId: rideId,
        seatsBooked: widget.seats,
        pickup: widget.pickup,
        destination: widget.destination,
      );

      UserSession.activeRideId =
          result['ride_id']?.toString() ?? rideId;

      if (!mounted) return;

      TopRightAlert.show(
        context,
        title: 'Ride booked',
        message: 'Request sent to ${driver['name']}.',
        isError: false,
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RideConfirmationScreen(
            driver: driver,
            pickup: widget.pickup,
            destination: widget.destination,
            rideId: UserSession.activeRideId,
            requestId: result['id']?.toString(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      TopRightAlert.show(
        context,
        title: 'Booking Failed',
        message: e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }
}
