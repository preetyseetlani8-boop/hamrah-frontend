import 'package:finalyearproject/screens/DriversScreen.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../widgets/osm_live_tracking_map.dart';

class CheckingCarsScreen extends StatefulWidget {
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

  const CheckingCarsScreen({
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
  State<CheckingCarsScreen> createState() => _CheckingCarsScreenState();
}

class _CheckingCarsScreenState extends State<CheckingCarsScreen> {
  int secondsElapsed = 0;
  Timer? _timer;
  bool showRideDetails = false;

  @override
  void initState() {
    super.initState();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => secondsElapsed++);

      if (secondsElapsed == 5) {
        _timer?.cancel();

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AvailableDriversScreen(
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
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get formattedTime {
    final mins = (secondsElapsed ~/ 60).toString().padLeft(2, '0');
    final secs = (secondsElapsed % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // English map + only pickup to destination route
          Positioned.fill(
            child: OsmLiveTrackingMap(
              pickupText: widget.pickup,
              destinationText: widget.destination,
              enableLiveLocation: false,
            ),
          ),

          DraggableScrollableSheet(
            initialChildSize: 0.42,
            minChildSize: 0.38,
            maxChildSize: 0.55,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 15),
                  ],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 50,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Searching for rides',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF212121),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00897B).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              formattedTime,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF00897B),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),
                      _buildSearchingDots(),
                      const SizedBox(height: 20),

                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F4F7),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            _summaryRow(
                              icon: Icons.my_location,
                              iconColor: const Color(0xFF00897B),
                              label: 'Pickup Location',
                              value: widget.pickup,
                            ),
                            Divider(
                              height: 1,
                              color: Colors.grey.shade300,
                              indent: 16,
                              endIndent: 16,
                            ),
                            _summaryRow(
                              icon: Icons.location_on,
                              iconColor: Colors.redAccent,
                              label: 'Destination',
                              value: widget.destination,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      GestureDetector(
                        onTap: () =>
                            setState(() => showRideDetails = !showRideDetails),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F4F7),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.receipt_long_outlined,
                                size: 18,
                                color: Color(0xFF00897B),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Ride Details',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF212121),
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                showRideDetails
                                    ? Icons.keyboard_arrow_down
                                    : Icons.keyboard_arrow_right,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (showRideDetails)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F4F7),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Column(
                            children: [
                              _detailRow('Vehicle', widget.vehicleType),
                              const SizedBox(height: 8),
                              _detailRow('Estimated Time', '12 mins'),
                            ],
                          ),
                        ),

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF212121),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 17),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Cancel Ride',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchingDots() {
    return Row(
      children: List.generate(3, (i) {
        return Container(
          margin: const EdgeInsets.only(right: 5),
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (secondsElapsed % 3) == i
                ? const Color(0xFF00897B)
                : Colors.grey.shade300,
          ),
        );
      }),
    );
  }

  Widget _summaryRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF212121),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF212121),
          ),
        ),
      ],
    );
  }
}