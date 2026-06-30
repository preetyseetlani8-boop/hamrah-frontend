
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../widgets/top_right_alert.dart';
import '../services/location_service.dart';
import '../services/UserSession.dart';
import '../config/api_config.dart';
import '../widgets/osm_live_tracking_map.dart';
import 'RateDriver.dart';
import 'CallScreen.dart';
import 'ChatScreen.dart';
import 'Ridebook.dart';

class LiveRideScreen extends StatefulWidget {
  final Map<String, dynamic> driver;
  final String pickup;
  final String destination;
  final String? rideId;

  const LiveRideScreen({
    super.key,
    required this.driver,
    required this.pickup,
    required this.destination,
    this.rideId,
  });

  @override
  State<LiveRideScreen> createState() => _LiveRideScreenState();
}

class _LiveRideScreenState extends State<LiveRideScreen> {
  int secondsElapsed = 0;
  Timer? _timer;
  Timer? _locationTimer;
  Timer? _statusTimer;
  double rideProgress = 0.0;
  String _statusLabel = 'Waiting for driver';
  WebSocketChannel? _wsChannel;
  bool _completionHandled = false;
  bool _firstStatusCheck = true;

  String get _rideId =>
      widget.rideId ?? UserSession.activeRideId;

  String _str(dynamic value, [String fallback = '']) =>
      value?.toString() ?? fallback;

  String get _driverName =>
      _str(widget.driver['name'] ?? widget.driver['driver_name'], 'Driver');

  void _connectWebSocket() {
    if (_rideId.isEmpty) return;
    final wsBase = ApiConfig.baseUrl.replaceFirst('http', 'ws');
    final url = '$wsBase/location/ws/$_rideId?token=${UserSession.token}';
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(url));
      _wsChannel!.stream.listen((message) {
        try {
          final data = jsonDecode(message as String);
          final msgType = data['type']?.toString();
          if (msgType == 'status_update') {
            final status = data['status']?.toString();
            _handleStatusUpdate(status);
          } else if (msgType == 'passenger_status_update') {
            // Targeted per-passenger status update from driver action
            final myRequestId = UserSession.activeRequestId;
            final eventRequestId = data['request_id']?.toString();
            // Process if it targets this passenger or is a broadcast (no passenger_id filter)
            if (myRequestId.isEmpty || myRequestId == eventRequestId ||
                data['passenger_id']?.toString() == UserSession.userId) {
              final reqStatus = data['request_status']?.toString() ?? data['status']?.toString();
              _handleStatusUpdate(reqStatus);
            }
          }
        } catch (_) {}
      }, onError: (_) {
        _wsChannel = null;
      }, onDone: () {
        _wsChannel = null;
      });
    } catch (_) {}
  }

  bool _isCompletedStatus(String? status) =>
      status == 'completed' || status == 'finished' || status == 'dropped';

  void _handleStatusUpdate(String? status) {
    if (!mounted || status == null) return;

    if (_isCompletedStatus(status)) {
      setState(() => _statusLabel = '✅ Completed');
      _navigateToReview();
      return;
    }

    setState(() {
      if (status == 'arrived' || status == 'pickup') {
        // 'pickup' is the new request_status when driver marks arrived
        _statusLabel = '📍 Driver Has Arrived!';
      } else if (status == 'ongoing' || status == 'riding') {
        _statusLabel = '🚗 Ride in progress';
      } else if (status == 'cancelled' ||
          status == 'cancelled_by_driver' ||
          status == 'cancelled_by_passenger') {
        _statusLabel = '❌ Cancelled';
        _handleRideCancelled();
      } else {
        _statusLabel = 'Waiting for driver';
      }
    });
  }

  void _handleRideCancelled() {
    if (_completionHandled) return;
    _timer?.cancel();
    _locationTimer?.cancel();
    _statusTimer?.cancel();
    _wsChannel?.sink.close();
    TopRightAlert.show(context,
        title: 'Ride Cancelled',
        message: 'The ride has been cancelled.',
        isError: true);
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RideSearchScreen()),
      (route) => false,
    );
  }

  void _navigateToReview() {
    if (_completionHandled || !mounted) return;
    _completionHandled = true;

    _timer?.cancel();
    _locationTimer?.cancel();
    _statusTimer?.cancel();
    _wsChannel?.sink.close();

    if (_rideId.isNotEmpty) UserSession.activeRideId = _rideId;

    TopRightAlert.show(context,
        title: 'Ride completed',
        message: 'Rate your driver.',
        isError: false);

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => RateDriverScreen(
          driver: {
            ...widget.driver,
            'name': _driverName,
            'ride_id': int.tryParse(_rideId) ?? _rideId,
            'fare': widget.driver['price'] ?? widget.driver['fare'] ?? '',
          },
        ),
      ),
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    if (_rideId.isNotEmpty) {
      UserSession.activeRideId = _rideId;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        secondsElapsed++;
        rideProgress = (secondsElapsed / 60).clamp(0.0, 1.0);
      });
    });
    _locationTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _sendLocationToBackend();
    });
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkStatus();
    });
    _checkStatus();
    _connectWebSocket();
  }

  Future<void> _checkStatus() async {
    if (_rideId.isEmpty || _completionHandled) return;
    try {
      final response = await http.get(
        ApiConfig.uri('/ride_requests/active'),
        headers: ApiConfig.jsonHeaders(),
      );
      if (response.statusCode == 200) {
        if (response.body == 'null' || response.body.isEmpty) {
          if (!_firstStatusCheck) {
            _navigateToReview();
          }
          _firstStatusCheck = false;
          return;
        }
        _firstStatusCheck = false;

        final data = jsonDecode(response.body);
        final status = data['status']?.toString();
        final reqStatus = data['request_status']?.toString();

        // New statuses: pickup = driver arrived, riding = in progress, dropped = completed
        if (_isCompletedStatus(status) || _isCompletedStatus(reqStatus) ||
            reqStatus == 'dropped' || reqStatus == 'rated') {
          _navigateToReview();
        } else {
          // Map new request statuses to status update handler
          final effectiveStatus = reqStatus == 'pickup' ? 'arrived'
              : reqStatus == 'riding' ? 'ongoing'
              : (status ?? reqStatus);
          _handleStatusUpdate(effectiveStatus);
        }
      } else if (response.statusCode == 401) {
        // Auth expired — api_client interceptor handles the redirect
      }
    } catch (_) {}
  }

  Future<void> _sendLocationToBackend() async {
    if (_rideId.isEmpty) return;
    try {
      final position = await Geolocator.getCurrentPosition();
      await LocationService.updateRideLocation(
        rideId: _rideId,
        latitude: position.latitude,
        longitude: position.longitude,
        role: 'passenger',
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _locationTimer?.cancel();
    _statusTimer?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }

  String get _elapsed {
    final m = (secondsElapsed ~/ 60).toString().padLeft(2, '0');
    final s = (secondsElapsed % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _endRide() => _navigateToReview();

  Future<void> _sos() async {
    try {
      final response = await http.get(
        ApiConfig.uri('/sos/contacts'),
        headers: ApiConfig.jsonHeaders(),
      );
      if (response.statusCode == 200) {
        final contacts = jsonDecode(response.body) as List;
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('🆘 Emergency Contacts',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                ),
                ...contacts.map((c) => ListTile(
                  leading: const Icon(Icons.call, color: Colors.red),
                  title: Text(_str(c['name'], 'Contact')),
                  subtitle: Text(_str(c['number'])),
                  onTap: () {
                    Navigator.pop(context);
                    launchUrl(Uri.parse('tel:${c['number']}'));
                  },
                )),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      }
    } catch (_) {
      TopRightAlert.show(context,
          title: '🆘 Emergency',
          message: 'Call 15 (Police) or 1122 (Rescue)',
          isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = _str(widget.driver['vehicle'], 'Vehicle');
    final plate = _str(widget.driver['plate'], '');

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: OsmLiveTrackingMap(
              pickupText: widget.pickup,
              destinationText: widget.destination,
              enableLiveLocation: true,
            ),
          ),

          // Top: back button + SOS (similar to waiting page menu position)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Material(
                    elevation: 4,
                    shape: const CircleBorder(),
                    color: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: Color(0xFF00897B)),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Spacer(),
                  Material(
                    elevation: 3,
                    shape: const CircleBorder(),
                    color: Colors.redAccent,
                    child: IconButton(
                      icon: const Icon(Icons.sos, color: Colors.white, size: 20),
                      onPressed: _sos,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom sheet — same look as waiting page
          DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.5,
            maxChildSize: 0.92,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: 50, height: 5,
                          decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Status banner (similar to waiting page active ride banner) ──
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00897B), Color(0xFF26A69A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00897B).withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.directions_car,
                                  color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _statusLabel,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Elapsed: $_elapsed',
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Trip details header (same as waiting page)
                      const Text('Trip details',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: Color(0xFF00897B))),
                      const SizedBox(height: 16),

                      // Driver card (compact, like waiting page)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F4F7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: const Color(0xFFE0F2F1),
                              child: Icon(
                                widget.driver['gender'] == 'Female'
                                    ? Icons.face_3 : Icons.face,
                                color: const Color(0xFF00897B), size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_driverName,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF212121)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  Text(
                                    '$vehicle  •  $plate',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Route inputs (same style as waiting page location inputs)
                      _routeInputRow(
                        icon: Icons.my_location,
                        iconColor: const Color(0xFF00897B),
                        label: 'Pickup',
                        value: widget.pickup,
                      ),
                      const SizedBox(height: 10),
                      _routeInputRow(
                        icon: Icons.location_on,
                        iconColor: Colors.redAccent,
                        label: 'Destination',
                        value: widget.destination,
                      ),
                      const SizedBox(height: 16),

                      // Progress bar (extra info for live ride)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ride progress',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700)),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: rideProgress,
                              minHeight: 8,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF00897B)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Action buttons (Call | Chat) — same as waiting page
                      Row(
                        children: [
                          Expanded(
                            child: _actionButton(
                              icon: Icons.call_outlined,
                              label: 'Call',
                              color: const Color(0xFF00897B),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CallScreen(
                                    contactName: _driverName,
                                    contactPhone:
                                    _str(widget.driver['phone']),
                                    callerRole: 'passenger',
                                    vehicleInfo: '$vehicle  •  $plate',
                                    rideId: _rideId.isNotEmpty ? _rideId : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _actionButton(
                              icon: Icons.chat_bubble_outline,
                              label: 'Message',
                              color: Colors.blue,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    contactName: _driverName,
                                    contactRole: 'driver',
                                    vehicleInfo: '$vehicle  •  $plate',
                                    rideRoute:
                                    '${widget.pickup}  →  ${widget.destination}',
                                    rideId: _rideId,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // End ride button (only for driver)
                      if (UserSession.isDriver)
                        SizedBox(
                          width: double.infinity, height: 55,
                          child: ElevatedButton.icon(
                            onPressed: _endRide,
                            icon: const Icon(Icons.flag_rounded, size: 20),
                            label: const Text('End Ride',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF212121),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15)),
                              elevation: 0,
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

  Widget _routeInputRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F7),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF212121)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ],
        ),
      ),
    );
  }
}
