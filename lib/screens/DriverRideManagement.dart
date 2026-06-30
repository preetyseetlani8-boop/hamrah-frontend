// lib/screens/driver_ride_management_screen.dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/ride_services.dart';
import '../services/location_service.dart';
import '../services/api_client.dart';
import 'RideHistoryScreen.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/top_right_alert.dart';
import '../services/UserSession.dart';
import '../widgets/osm_live_tracking_map.dart';
import 'DriverDashboard.dart';
import 'CallScreen.dart';
import 'ChatScreen.dart';
import 'RatePassengerScreen.dart';
import '../config/api_config.dart';

class DriverRideManagementScreen extends StatefulWidget {
  final Map<String, dynamic>? request;
  const DriverRideManagementScreen({super.key, required this.request});

  @override
  State<DriverRideManagementScreen> createState() =>
      _DriverRideManagementScreenState();
}

class _DriverRideManagementScreenState
    extends State<DriverRideManagementScreen> {

  String _rideState = 'heading'; // heading | arrived | inProgress | completed
  int secondsElapsed = 0;
  Timer? _timer;
  Timer? _locationTimer;
  WebSocketChannel? _wsChannel;
  bool _completionHandled = false;

  String _str(dynamic value, [String fallback = '']) =>
      value?.toString() ?? fallback;

  // ── EXACT BACKEND KEY ALIGNMENT ─────────────────────────────────────
  List<Map<String, dynamic>> get _passengers {
    final req = widget.request;
    if (req == null) return [];

    // Matches the "accepted_passengers" list key from your FastAPI router
    final dynamic listData = req['accepted_passengers'];
    if (listData != null && listData is List) {
      return List<Map<String, dynamic>>.from(listData);
    }

    // Single passenger object fallback fallback match
    if (req['passenger'] != null && req['passenger'] is Map) {
      return [Map<String, dynamic>.from(req['passenger'])];
    }

    return [];
  }

  int get _totalFare {
    final req = widget.request;
    // Fallback default calculation utilizing backend's flat "fare_per_seat" field
    final baseFare = (double.tryParse(req?['fare_per_seat']?.toString() ?? '0') ?? 0).toInt();

    if (_passengers.isEmpty) return baseFare;

    return _passengers.fold<int>(0, (sum, p) {
      final fareVal = p['fare'] ?? p['price'] ?? baseFare;
      final parsedFare = (double.tryParse(fareVal.toString()) ?? baseFare.toDouble()).toInt();
      return sum + parsedFare;
    });
  }

  int get _totalSeats {
    return _passengers.fold<int>(0, (sum, p) {
      final seatVal = p['seats'] ?? p['requested_seats'] ?? 1;
      return sum + (int.tryParse(seatVal.toString()) ?? 1);
    });
  }

  void _connectWebSocket() {
    final rideId = UserSession.activeRideId;
    if (rideId.isEmpty) return;
    final wsBase = ApiConfig.baseUrl.replaceFirst('http', 'ws');
    final url = '$wsBase/location/ws/$rideId?token=${UserSession.token}';
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(url));
      _wsChannel!.stream.listen((message) {
        try {
          final data = jsonDecode(message as String);
          if (data['type'] == 'status_update') {
            final status = data['status']?.toString();
            if (status == 'completed' || status == 'finished') {
              _handleRideCompleted(fromRemote: true);
            } else if (status == 'cancelled' ||
                status == 'cancelled_by_driver' ||
                status == 'cancelled_by_passenger') {
              _handleRideCancelled();
            }
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  void _handleRideCancelled() {
    _timer?.cancel();
    _locationTimer?.cancel();
    _wsChannel?.sink.close();
    TopRightAlert.show(context,
        title: 'Ride Cancelled',
        message: 'The ride has been cancelled.',
        isError: true);
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const DriverDashboardScreen()),
      (route) => false,
    );
  }

  void _openReviewScreen() {
    final req = widget.request;
    final rideId = _str(req?['id'] ?? req?['ride_id'], UserSession.activeRideId);
    if (rideId.isNotEmpty) UserSession.activeRideId = rideId;

    if (_passengers.isEmpty) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DriverDashboardScreen()),
        (route) => false,
      );
      return;
    }

    final pList = List<Map<String, dynamic>>.from(_passengers);
    final firstPassenger = pList.removeAt(0);

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => RatePassengerScreen(
          passenger: firstPassenger,
          rideId: rideId,
          isSinglePassenger: false,
          remainingPassengers: pList,
        ),
      ),
      (route) => false,
    );
  }

  void _handleRideCompleted({bool fromRemote = false}) {
    if (_completionHandled || !mounted) return;
    _completionHandled = true;

    _timer?.cancel();
    _locationTimer?.cancel();
    _wsChannel?.sink.close();

    if (!fromRemote) {
      setState(() => _rideState = 'completed');
    }

    TopRightAlert.show(context,
        title: 'Ride Completed ✅',
        message: 'Rate your passengers.',
        isError: false);

    _openReviewScreen();
  }

  void _sendSocketStatus(String status) {
    if (_wsChannel == null) {
      _connectWebSocket();
    }
    try {
      _wsChannel?.sink.add(jsonEncode({
        'type': 'status_update',
        'status': status,
      }));
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    if (widget.request != null) {
      // Pulls top-level ride "id" parameter assigned by FastAPI backend
      final rideId = widget.request!['id']?.toString() ??
          widget.request!['ride_id']?.toString() ?? '';
      if (rideId.isNotEmpty) UserSession.activeRideId = rideId;

      final status = widget.request!['status']?.toString();
      if (status == 'ongoing') {
        _rideState = 'inProgress';
      } else if (status == 'arrived') {
        _rideState = 'arrived';
      } else if (status == 'completed') {
        _rideState = 'completed';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleRideCompleted(fromRemote: true);
        });
      } else {
        _rideState = 'heading';
      }

      _connectWebSocket();
      _startTimer();
      _locationTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        _sendDriverLocation();
      });
    }
  }

  Future<void> _sendDriverLocation() async {
    final rideId = UserSession.activeRideId;
    if (rideId.isEmpty) return;
    try {
      final position = await Geolocator.getCurrentPosition();
      await LocationService.updateRideLocation(
        rideId: rideId,
        latitude: position.latitude,
        longitude: position.longitude,
        role: 'driver',
      );
    } catch (_) {}
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) {
        setState(() {
          secondsElapsed++;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _locationTimer?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }

  Future<void> _completeWholeRide() async {
    final rideId = widget.request?['id']?.toString() ??
        widget.request?['ride_id']?.toString() ??
        UserSession.activeRideId;

    if (rideId.isEmpty) return;

    try {
      await RideService.completeRide(rideId);
    } catch (e) {
      final msg = e.toString();
      if (!msg.contains('completed') && !msg.contains('complete')) {
        if (mounted) {
          TopRightAlert.show(context,
              title: 'Error', message: msg.replaceFirst('Exception: ', ''), isError: true);
        }
        return;
      }
    }
    _sendSocketStatus('completed');
    _handleRideCompleted();
  }

  Future<void> _cancelWholeRide() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Ride?'),
        content: const Text('Are you sure you want to cancel this entire ride? All passengers will be notified.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final rideId = widget.request?['id']?.toString() ??
        widget.request?['ride_id']?.toString() ??
        UserSession.activeRideId;

    if (rideId.isEmpty) return;

    try {
      await RideService.cancelRide(rideId);
      _sendSocketStatus('cancelled');
      _handleRideCancelled();
    } catch (e) {
      if (mounted) {
        TopRightAlert.show(context,
            title: 'Error',
            message: e.toString().replaceFirst('Exception: ', ''),
            isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.request == null) return const RideHistoryScreen();
    return _buildActiveRideView();
  }

  Widget _buildActiveRideView() {
    final req = widget.request!;
    // Count ONLY active passengers (not dropped or rated)
    final activeList = _passengers.where((p) {
      final s = p['status']?.toString() ?? '';
      return s != 'dropped' && s != 'rated';
    }).toList();
    final bool allDropped = _passengers.isNotEmpty &&
        _passengers.every((p) {
          final s = p['status']?.toString() ?? '';
          return s == 'dropped' || s == 'rated';
        });
    final bool allDone = allDropped;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: OsmLiveTrackingMap(
              pickupText: req['from_address'] ?? req['pickup'] ?? '',
              destinationText: req['to_address'] ?? req['destination'] ?? '',
              enableLiveLocation: true,
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Material(
                    elevation: 3, shape: const CircleBorder(),
                    color: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: Color(0xFF00897B), size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
          ),

          DraggableScrollableSheet(
            initialChildSize: 0.55,
            minChildSize: 0.38,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 50, height: 5,
                          decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Text(
                        'Ride Management',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF00897B)),
                      ),
                      const SizedBox(height: 12),

                      Text(
                        'Passengers (${activeList.length})',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                            letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),

                      Column(
                        children: List.generate(activeList.length, (index) {
                          final p = activeList[index];
                          return _buildPassengerCard(p, req);
                        }),
                      ),
                      const SizedBox(height: 20),

                      if (_rideState != 'completed' && !allDone) ...[
                        // 'Complete All Rides' only shown when all are riding
                        if (_passengers.isNotEmpty && _passengers.every((p) =>
                            (p['status']?.toString() ?? '') == 'riding')) ...[
                          SizedBox(
                            width: double.infinity, height: 55,
                            child: ElevatedButton(
                              onPressed: _completeWholeRide,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey.shade800,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15)),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Complete All Rides',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        SizedBox(
                          width: double.infinity, height: 55,
                          child: OutlinedButton(
                            onPressed: _cancelWholeRide,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red, width: 1.5),
                              foregroundColor: Colors.red,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15)),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Cancel Ride',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],

                      if (_rideState == 'completed' || allDone) ...[
                        Container(
                          padding: const EdgeInsets.all(20),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00897B).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: const Color(0xFF00897B).withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  color: Color(0xFF00897B), size: 40),
                              const SizedBox(height: 8),
                              Text(
                                  'Rs. $_totalFare',
                                  style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF00897B))),
                              Text('Total payment from $_totalSeats seats received',
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.grey)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity, height: 55,
                          child: ElevatedButton(
                            onPressed: _openReviewScreen,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF212121),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15)),
                              elevation: 0,
                            ),
                            child: const Text('Rate passengers',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
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

  Widget _buildPassengerCard(Map<String, dynamic> passenger, Map<String, dynamic> globalReq) {
    final pName = passenger['name'] ?? 'Passenger';
    final pPhone = passenger['phone'] ?? '';
    final pSeats = passenger['seats'] ?? passenger['requested_seats'] ?? 1;
    final int baseFare = (double.tryParse(globalReq['fare_per_seat']?.toString() ?? '0') ?? 0).toInt();
    final pFare = (double.tryParse((passenger['fare'] ?? passenger['price'] ?? baseFare).toString()) ?? baseFare.toDouble()).toInt() * pSeats;
    final pGender = passenger['gender']?.toString() ?? 'Unknown';

    final pPickup = globalReq['from_address'] ?? 'Pickup';
    final pDropoff = globalReq['to_address'] ?? 'Destination';
    final currentStatus = passenger['status']?.toString() ?? 'accepted';

    return GestureDetector(
      onTap: () => _showPassengerMenu(passenger),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F4F7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFE0F2F1),
                  child: Icon(
                    pGender == 'Female' ? Icons.face_3 : Icons.face,
                    color: const Color(0xFF00897B), size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pName,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF212121)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '$pSeats seat${pSeats > 1 ? 's' : ''}  •  Rs. $pFare',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF00897B),
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              contactName: pName,
                              contactRole: 'passenger',
                              rideRoute: '$pPickup → $pDropoff',
                              rideId: _str(globalReq['id'] ?? globalReq['ride_id'], UserSession.activeRideId),
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.chat_bubble_outline, color: Colors.blue, size: 20),
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CallScreen(
                              contactName: pName,
                              contactPhone: pPhone,
                              callerRole: 'driver',
                              rideId: _str(globalReq['id'] ?? globalReq['ride_id'], UserSession.activeRideId),
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.call_outlined, color: Color(0xFF00897B), size: 20),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6.0),
              child: Divider(height: 1, color: Colors.black12),
            ),
            
            // Passenger State Stepper
            _buildPassengerStepper(currentStatus),
            const SizedBox(height: 12),

            // Card Action Buttons
            _buildPassengerActionButtons(passenger),
            
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6.0),
              child: Divider(height: 1, color: Colors.black12),
            ),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '$pPickup → $pDropoff',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPassengerStepper(String currentStatus) {
    final steps = ['Accepted', 'Arrived', 'Riding', 'Dropped'];
    final idxMap = {
      'accepted': 0,
      'pickup':   1,   // driver physically arrived at pickup point
      'arrived':  1,   // legacy
      'riding':   2,
      'picked_up': 2,  // legacy
      'dropped':  3,
      'rated':    3,
      'completed': 3,
    };
    final idx = idxMap[currentStatus] ?? 0;

    return Row(
      children: List.generate(steps.length, (i) {
        final done   = i <= idx;
        final active = i == idx;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: active ? 20 : 14, height: active ? 20 : 14,
                      decoration: BoxDecoration(
                        color: done ? const Color(0xFF00897B) : Colors.grey.shade200,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: done ? const Color(0xFF00897B) : Colors.grey.shade300,
                          width: 1.2,
                        ),
                      ),
                      child: done
                          ? const Icon(Icons.check, color: Colors.white, size: 9)
                          : null,
                    ),
                    const SizedBox(height: 3),
                    Text(steps[i],
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 7,
                            fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                            color: done ? const Color(0xFF00897B) : Colors.grey.shade400)),
                  ],
                ),
              ),
              if (i < steps.length - 1)
                Expanded(
                  child: Container(
                    height: 1.5,
                    margin: const EdgeInsets.only(bottom: 10),
                    color: i < idx ? const Color(0xFF00897B) : Colors.grey.shade200,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildPassengerActionButtons(Map<String, dynamic> passenger) {
    final currentStatus = passenger['status']?.toString() ?? 'pickup';
    final requestId = passenger['request_id']?.toString() ?? '';

    // Passenger is done — no action button
    if (currentStatus == 'dropped' || currentStatus == 'rated') {
      return const SizedBox.shrink();
    }

    String btnText = 'I Have Arrived';
    String action = 'arrive';
    Color btnColor = Colors.orange;

    if (currentStatus == 'accepted') {
      // Just accepted — driver is en route, must mark arrived first
      btnText = 'I Have Arrived';
      action = 'arrive';
      btnColor = Colors.orange;
    } else if (currentStatus == 'pickup') {
      // Driver has arrived at pickup point — next is start ride
      btnText = 'Start Ride / Pick Up';
      action = 'pickup';
      btnColor = const Color(0xFF00897B);
    } else if (currentStatus == 'riding' || currentStatus == 'picked_up') {
      btnText = 'Drop Off Passenger';
      action = 'complete';
      btnColor = Colors.blue;
    }

    return SizedBox(
      width: double.infinity,
      height: 38,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: btnColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () => _updatePassengerStatus(requestId, action),
        child: Text(
          btnText,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _showPassengerMenu(Map<String, dynamic> passenger) {
    final requestId = passenger['request_id']?.toString() ?? '';
    final pName = passenger['name'] ?? 'Passenger';
    final currentStatus = passenger['status']?.toString() ?? 'accepted';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Manage $pName',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              if (currentStatus == 'accepted')
                ListTile(
                  leading: const Icon(Icons.location_on, color: Colors.orange),
                  title: const Text('Mark as Arrived'),
                  subtitle: const Text('Driver has arrived at passenger\'s pickup'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _updatePassengerStatus(requestId, 'arrive');
                  },
                ),
              if (currentStatus == 'pickup' || currentStatus == 'arrived')
                ListTile(
                  leading: const Icon(Icons.directions_run, color: Color(0xFF00897B)),
                  title: const Text('Mark as In Progress (Picked Up)'),
                  subtitle: const Text('Passenger is now in the vehicle'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _updatePassengerStatus(requestId, 'pickup');
                  },
                ),
              if (currentStatus == 'riding' || currentStatus == 'picked_up')
                ListTile(
                  leading: const Icon(Icons.check_circle_outline, color: Colors.blue),
                  title: const Text('Mark as Completed'),
                  subtitle: const Text('Passenger dropped off safely'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _updatePassengerStatus(requestId, 'complete');
                  },
                ),
            ],
          ),
        );
      },
    );
  }
  Future<void> _updatePassengerStatus(String requestId, String action) async {
    if (requestId.isEmpty) return;
    try {
      final response = await http.post(
        ApiConfig.uri('/rides/requests/$requestId/$action'),
        headers: ApiConfig.jsonHeaders(),
      );
      
      final data = ApiClient.decode(response);
      ApiClient.ensureSuccess(response, data);

      final statusStr = action == 'arrive'
          ? 'pickup'
          : action == 'pickup'
              ? 'riding'
              : 'dropped';

      _sendSocketStatus(statusStr);

      if (mounted) {
        TopRightAlert.show(context,
            title: 'Success',
            message: 'Passenger status updated.',
            isError: false);
      }

      setState(() {
        final list = widget.request?['accepted_passengers'] as List?;
        if (list != null) {
          for (var p in list) {
            if (p is Map && p['request_id']?.toString() == requestId) {
              p['status'] = statusStr;
            }
          }
        }
      });

      // If the driver just dropped a passenger, check if ALL are dropped
      if (action == 'complete' && mounted) {
        final allDroppedNow = _passengers.every((p) {
          final s = p['status']?.toString() ?? '';
          return s == 'dropped' || s == 'rated';
        });

        if (allDroppedNow) {
          // All passengers dropped — end ride, navigate to rating
          _timer?.cancel();
          _locationTimer?.cancel();
          _wsChannel?.sink.close();
          TopRightAlert.show(context,
              title: 'Ride Completed ✅',
              message: 'All passengers dropped. Rate your passengers.',
              isError: false);
          _openReviewScreen();
        } else {
          // Still more active passengers — just show single-passenger rate screen
          final rideId = widget.request?['id']?.toString() ??
              widget.request?['ride_id']?.toString() ??
              UserSession.activeRideId;
          // Find the passenger we just dropped
          final droppedPassenger = _passengers.firstWhere(
            (p) => p['request_id']?.toString() == requestId,
            orElse: () => {},
          );
          if (droppedPassenger.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RatePassengerScreen(
                  passenger: droppedPassenger,
                  rideId: rideId,
                  isSinglePassenger: true,
                ),
              ),
            ).then((_) {
              if (mounted) setState(() {});
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        TopRightAlert.show(context,
            title: 'Error',
            message: e.toString().replaceFirst('Exception: ', ''),
            isError: true);
      }
    }
  }}