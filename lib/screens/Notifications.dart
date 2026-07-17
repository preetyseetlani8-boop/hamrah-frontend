// lib/screens/notifications_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';
import '../services/firebase_notification_service.dart';
import 'Ridebook.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final FirebaseNotificationService _notificationService =
      FirebaseNotificationService.instance;
  late final StreamSubscription<AppNotification> _notificationSubscription;

  List<AppNotification> _notifications = [];
  bool _loadingHistory = true;

  // Unified handler for ride recommendation notification taps
  void _handleNotificationTap(AppNotification notif) {
    setState(() => notif.read = true);

    // Handle ride recommendation specifically
    if (notif.type == 'ride_recommendation' ||
        (notif.data['type']?.toString() ?? '') == 'ride_recommendation') {
      // Parse the data to pass to RideSearchScreen
      final rideId = notif.data['ride_id']?.toString() ?? '';
      final from   = notif.data['from_address']?.toString() ?? '';
      final to     = notif.data['to_address']?.toString() ?? '';

      double? fromLat;
      double? fromLng;
      double? toLat;
      double? toLng;
      DateTime? departureTime;

      if (notif.data['from_lat'] != null && notif.data['from_lat'].toString().isNotEmpty) {
        fromLat = double.tryParse(notif.data['from_lat'].toString());
      }
      if (notif.data['from_lng'] != null && notif.data['from_lng'].toString().isNotEmpty) {
        fromLng = double.tryParse(notif.data['from_lng'].toString());
      }
      if (notif.data['to_lat'] != null && notif.data['to_lat'].toString().isNotEmpty) {
        toLat = double.tryParse(notif.data['to_lat'].toString());
      }
      if (notif.data['to_lng'] != null && notif.data['to_lng'].toString().isNotEmpty) {
        toLng = double.tryParse(notif.data['to_lng'].toString());
      }

      if (notif.data['departure_time'] != null && notif.data['departure_time'].toString().isNotEmpty) {
        try {
          departureTime = DateTime.parse(notif.data['departure_time'].toString());
        } catch (e) {
          debugPrint('Could not parse departure time: $e');
        }
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RideSearchScreen(
            prefillRideId: rideId,
            prefillFrom: from,
            prefillTo: to,
            prefillFromLat: fromLat,
            prefillFromLng: fromLng,
            prefillToLat: toLat,
            prefillToLng: toLng,
            prefillDepartureTime: departureTime,
          ),
        ),
      );
      return;
    }
  }

  @override
  void initState() {
    super.initState();
    _notifications = List<AppNotification>.from(_notificationService.notifications);
    _notificationSubscription =
        _notificationService.notificationsStream.listen((_) {
      if (!mounted) return;
      setState(() {
        _notifications =
            List<AppNotification>.from(_notificationService.notifications);
      });
    });
    _loadHistory();
  }

  // Fetches saved history from the backend (includes AI ride recommendations
  // and any other notification generated while the app wasn't running).
  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    await _notificationService.loadHistoryFromBackend();
    if (!mounted) return;
    setState(() {
      _notifications = List<AppNotification>.from(_notificationService.notifications);
      _loadingHistory = false;
    });
  }

  @override
  void dispose() {
    _notificationSubscription.cancel();
    super.dispose();
  }

  void _markAllRead() {
    setState(() {
      for (final n in _notifications) {
        n.read = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifications.where((n) => !n.read).length;

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
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new,
                          color: Color(0xFF00897B)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text('Notifications',
                          style: TextStyle(
                              color: Color(0xFF00897B),
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ),
                    if (_loadingHistory)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF00897B),
                          ),
                        ),
                      ),
                    if (unread > 0)
                      TextButton(
                        onPressed: _markAllRead,
                        child: const Text('Mark all read',
                            style: TextStyle(
                                color: Color(0xFF00897B),
                                fontSize: 13)),
                      ),
                  ],
                ),
              ),

              if (unread > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00897B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.notifications_active_outlined,
                            color: Color(0xFF00897B), size: 16),
                        const SizedBox(width: 8),
                        Text('$unread unread notification${unread > 1 ? 's' : ''}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF00897B))),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),

              Expanded(
                child: _notifications.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _notifications.length,
                  itemBuilder: (context, i) =>
                      _notifCard(_notifications[i], i),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notifCard(AppNotification notif, int index) {
    final iconData = {
      'ride': Icons.directions_car_outlined,
      'ride_recommendation': Icons.directions_car_outlined,
      'payment': Icons.payments_outlined,
      'rating': Icons.star_outline_rounded,
      'promo': Icons.local_offer_outlined,
      'system': Icons.verified_outlined,
    }[notif.type] ?? Icons.notifications_outlined;

    final iconColor = {
      'ride': const Color(0xFF00897B),
      'ride_recommendation': const Color(0xFF00897B),
      'payment': Colors.blue,
      'rating': Colors.amber,
      'promo': Colors.purple,
      'system': Colors.teal,
    }[notif.type] ?? const Color(0xFF00897B);

    return GestureDetector(
      onTap: () => _handleNotificationTap(notif),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notif.read
              ? Colors.white.withOpacity(0.88)
              : Colors.white.withOpacity(0.98),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: notif.read
                ? Colors.grey.shade100
                : const Color(0xFF00897B).withOpacity(0.3),
            width: notif.read ? 1 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(notif.read ? 0.03 : 0.07),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: iconColor.withOpacity(0.1),
              child: Icon(iconData, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(notif.title,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: notif.read
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                                color: const Color(0xFF212121))),
                      ),
                      if (!notif.read)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: Color(0xFF00897B),
                              shape: BoxShape.circle),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(notif.body,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.4)),
                  const SizedBox(height: 5),
                  Text(notif.time,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400)),
                ],
              ),
            ),
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
          Icon(Icons.notifications_off_outlined,
              size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text('No notifications yet',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('No new notifications',
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}