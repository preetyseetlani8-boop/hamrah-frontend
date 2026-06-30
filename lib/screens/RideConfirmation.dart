// lib/screens/ride_confirmation_screen.dart
//
// ADDED vs previous version:
//   - Call button → opens CallScreen
//   - Chat button → opens ChatScreen
//   - Share Ride button → uses share_plus to share a ride link
//
// pubspec.yaml — add these if not already present:
//   url_launcher: ^6.2.5
//   share_plus: ^7.2.1

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import '../widgets/top_right_alert.dart';
import '../widgets/osm_live_tracking_map.dart';
import '../services/UserSession.dart';
import '../config/api_config.dart';
import '../services/ride_services.dart';
import 'LiveDriverScreen.dart';
import 'CallScreen.dart';
import 'ChatScreen.dart';
import 'RateDriver.dart';
import 'Ridebook.dart';

class RideConfirmationScreen extends StatefulWidget {
  final Map<String, dynamic> driver;
  final String pickup;
  final String destination;
  final String? rideId;
  final String? requestId;

  const RideConfirmationScreen({
    super.key,
    required this.driver,
    required this.pickup,
    required this.destination,
    this.rideId,
    this.requestId,
  });

  @override
  State<RideConfirmationScreen> createState() => _RideConfirmationScreenState();
}

class _RideConfirmationScreenState extends State<RideConfirmationScreen> {
  Timer? _statusTimer;
  String? _lastStatus;
  String? _requestStatus = 'pending';
  bool _firstCheck = true;
  bool _navigatedToLive = false;
  String? _requestId;
  String? _statusLabel;

  @override
  void initState() {
    super.initState();
    _requestId = widget.requestId;
    _checkRideStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _checkRideStatus();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  void _showRatingScreen({String? rideId}) {
    _statusTimer?.cancel();
    if (!mounted) return;
    final rid = rideId ?? widget.rideId ?? UserSession.activeRideId;
    if (rid != null && rid.isNotEmpty) UserSession.activeRideId = rid;
    TopRightAlert.show(context,
        title: '✅ Ride Completed',
        message: 'You have reached your destination!',
        isError: false);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => RateDriverScreen(
            driver: {
              'name': widget.driver['name'] ?? 'Driver',
              'ride_id': int.tryParse(rid ?? '') ?? 0,
            },
          )),
          (route) => false,
        );
      }
    });
  }

  Future<void> _checkRideStatus() async {
    try {
      final response = await http.get(
        ApiConfig.uri('/ride_requests/active'),
        headers: ApiConfig.jsonHeaders(),
      );
      if (response.statusCode == 200) {
        // Null response means ride ended
        if (response.body == 'null' || response.body.isEmpty) {
          // Only show rating if we had a real active ride before
          if (!_firstCheck && _lastStatus != null && _lastStatus != 'null') {
            _showRatingScreen();
          }
          _firstCheck = false;
          return;
        }
        _firstCheck = false;

        final data = jsonDecode(response.body);
        _requestId = data?['request_id']?.toString() ?? data?['id']?.toString();
        final status = data?['status']?.toString();
        final reqStatus = data?['request_status']?.toString() ?? 'pending';
        _statusLabel = data?['status_label']?.toString();

        // Store request ID for WS event filtering
        if (_requestId != null && _requestId!.isNotEmpty) {
          UserSession.activeRequestId = _requestId!;
        }

        setState(() {
          _requestStatus = reqStatus;
        });

        if ((status == 'completed' || reqStatus == 'completed' ||
                reqStatus == 'dropped' || reqStatus == 'rated') &&
            _lastStatus != 'completed') {
          _showRatingScreen(rideId: data['ride_id']?.toString());
        } else if (!_navigatedToLive &&
            (reqStatus == 'accepted' ||
                reqStatus == 'pickup' ||
                reqStatus == 'riding' ||
                reqStatus == 'picked_up' ||
                status == 'ongoing' ||
                status == 'arrived')) {
          _navigatedToLive = true;
          _startRide();
        }
        _lastStatus = status ?? reqStatus;
      }
    } catch (_) {}
  }

  String _formatEta(String raw) {
    if (raw.isEmpty || raw == '--') return '--';
    try {
      final dt = DateTime.parse(raw);
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final p = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $p';
    } catch (_) { return raw; }
  }

  void _cancelRide() async {
    if (_requestId != null && _requestId!.isNotEmpty) {
      try {
        await RideService.cancelRequest(_requestId!);
      } catch (_) {}
    }
    TopRightAlert.show(context,
        title: 'Ride Cancelled',
        message: 'Your ride request has been cancelled.',
        isError: false);
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  void _startRide() {
    if (widget.rideId != null && widget.rideId!.isNotEmpty) {
      UserSession.activeRideId = widget.rideId!;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LiveRideScreen(
          driver: widget.driver,
          pickup: widget.pickup,
          destination: widget.destination,
          rideId: widget.rideId?.isNotEmpty == true
              ? widget.rideId!
              : widget.driver['ride_id']?.toString() ??
                widget.driver['id']?.toString() ??
                UserSession.activeRideId,
        ),
      ),
    );
  }

  void _openCall() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          contactName: widget.driver['name'] ?? 'Driver',
          contactPhone: widget.driver['phone']?.toString() ?? '',
          callerRole: 'passenger',
          vehicleInfo: '${widget.driver['vehicle']}  •  ${widget.driver['plate']}',
          rideId: widget.rideId?.isNotEmpty == true
              ? widget.rideId
              : widget.driver['ride_id']?.toString() ?? widget.driver['id']?.toString(),
        ),
      ),
    );
  }

  void _openChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          contactName: widget.driver['name'],
          contactRole: 'driver',
          vehicleInfo: '${widget.driver['vehicle']}  •  ${widget.driver['plate']}',
          rideRoute: '${widget.pickup}  →  ${widget.destination}',
          rideId: widget.rideId?.isNotEmpty == true
              ? widget.rideId!
              : widget.driver['ride_id']?.toString() ??
                widget.driver['id']?.toString() ??
                UserSession.activeRideId,
        ),
      ),
    );
  }

  void _shareRide() {
    final name   = widget.driver['name'];
    final car    = widget.driver['vehicle'];
    final plate  = widget.driver['plate'];
    final pickup = widget.pickup;
    final dest   = widget.destination;
    final fare   = widget.driver['price'];

    Share.share(
      'Hamrah ride details\n\n'
          'From: $pickup\n'
          'To: $dest\n'
          'Driver: $name\n'
          'Vehicle: $car ($plate)\n'
          'Fare: $fare\n\n'
          'Live tracking: https://hamrah.app/ride/live',
      subject: 'Hamrah ride — $pickup to $dest',
    );
  }

  bool get _isAccepted =>
      _requestStatus == 'accepted' ||
      _requestStatus == 'pickup' ||
      _requestStatus == 'riding' ||
      _requestStatus == 'picked_up' ||
      _lastStatus == 'ongoing' ||
      _lastStatus == 'arrived';

  @override
  Widget build(BuildContext context) {
    final driver = widget.driver;
    final isPending = !_isAccepted;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: OsmLiveTrackingMap(
              pickupText: widget.pickup,
              destinationText: widget.destination,
            ),
          ),

          // Top menu button (same as waiting page)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Material(
                elevation: 4,
                shape: const CircleBorder(),
                color: Colors.white,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: Color(0xFF00897B)),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),

          // Bottom sheet — similar style to waiting page
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

                      // ── Status banner (similar style to waiting page banner) ──
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
                              child: Icon(
                                isPending
                                    ? Icons.hourglass_top
                                    : (Icons.directions_car),
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isPending
                                        ? '⏳ Waiting for driver'
                                        : _getStatusLabel(),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isPending
                                        ? 'Your request was sent'
                                        : 'Tap chat/call to reach driver',
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

                      // Driver card (compact, similar to waiting page driver)
                      if (driver['name'] != null) ...[
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
                                  driver['gender'] == 'Female'
                                      ? Icons.face_3 : Icons.face,
                                  color: const Color(0xFF00897B), size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(driver['name'],
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF212121)),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    Text(
                                      '${driver['vehicle'] ?? 'Car'}  •  ${driver['plate'] ?? ''}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Text(driver['price']?.toString() ?? '',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF00897B))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Route (similar to waiting page location inputs)
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

                      // Action buttons (Call | Chat | Share) — same as before but compact
                      Row(
                        children: [
                          Expanded(
                            child: _actionButton(
                              icon: Icons.call_outlined,
                              label: 'Call',
                              color: const Color(0xFF00897B),
                              onTap: _isAccepted ? _openCall : () {},
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _actionButton(
                              icon: Icons.chat_bubble_outline,
                              label: 'Message',
                              color: Colors.blue,
                              onTap: _isAccepted ? _openChat : () {},
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _actionButton(
                              icon: Icons.share_outlined,
                              label: 'Share',
                              color: Colors.purple,
                              onTap: _shareRide,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Cancel button — only visible before ride starts
                      if (_requestStatus == 'pending' || _requestStatus == 'accepted')
                        OutlinedButton.icon(
                          onPressed: _cancelRide,
                          icon: const Icon(Icons.close,
                              color: Colors.redAccent, size: 18),
                          label: const Text('Cancel Ride',
                              style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15)),
                          ),
                        ),

                      // Start ride button — sirf driver ke liye
                      if (UserSession.isDriver)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: ElevatedButton.icon(
                            onPressed: _startRide,
                            icon: const Icon(Icons.play_arrow_rounded, size: 22),
                            label: const Text('Start ride',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 55),
                              backgroundColor: const Color(0xFF00897B),
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

  String _getStatusLabel() {
    switch (_requestStatus) {
      case 'pickup':
        return '📍 Driver Has Arrived!';
      case 'riding':
      case 'picked_up':
        return '🚗 Ride in progress';
      case 'dropped':
      case 'rated':
      case 'completed':
        return '✅ Completed';
      case 'accepted':
        return '✅ Driver Accepted';
      default:
        return _statusLabel ?? 'Ride in progress';
    }
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

  Widget _routeRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
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
    );
  }
}