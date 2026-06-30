// lib/screens/driver_dashboard_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../widgets/top_right_alert.dart';
import '../widgets/osm_live_tracking_map.dart';
import '../services/UserSession.dart';
import '../services/ride_services.dart';
import '../services/auth_service.dart';
import '../config/api_config.dart';
import '../utils/time_utils.dart';
import 'login_screen.dart';
import 'DriverRideManagement.dart';
import 'DriverEarnings.dart';
import 'DriverProfile.dart';
import 'RideHistoryScreen.dart';
import 'Notifications.dart';
import 'offerride.dart';
import 'Ridebook.dart';
import '../services/location_service.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isOnline = true;
  bool _loadingRequests = true;
  bool _loadingMyRides  = true;
  final List<Map<String, dynamic>> _requests = [];
  final List<Map<String, dynamic>> _myRides  = [];
  final List<Map<String, dynamic>> _activeRides = [];
  Timer? _refreshTimer;
  WebSocketChannel? _requestChannel;

  bool _isRideInProgress(Map<String,dynamic> ride){
  final status=ride['status']?.toString().toLowerCase()??'';
  return status=='ongoing'||status=='started'||status=='in_progress'||status=='active';
}

  Map<String, dynamic>? get _currentActiveRide {
    final activeId = UserSession.activeRideId;
    for (final ride in [..._myRides, ..._activeRides]) {
      final rideId = ride['id']?.toString() ?? ride['ride_id']?.toString() ?? '';
      if (_isRideInProgress(ride) &&
          (activeId.isEmpty || rideId == activeId || ride['ride_id']?.toString() == activeId)) {
        return ride;
      }
    }
    return null;
  }

  void _syncActiveRideId(List<Map<String, dynamic>> rides) {
    final ongoing = rides.where(_isRideInProgress).toList();
    if (ongoing.isEmpty) {
      UserSession.activeRideId = '';
      return;
    }

    final stillActive = ongoing.any((ride) {
      final rideId = ride['id']?.toString() ?? ride['ride_id']?.toString() ?? '';
      return rideId == UserSession.activeRideId ||
          ride['ride_id']?.toString() == UserSession.activeRideId;
    });

    if (!stillActive) {
      UserSession.activeRideId =
          ongoing.first['id']?.toString() ?? ongoing.first['ride_id']?.toString() ?? '';
    }
  }

  bool _hasPassengerRole = false;

  Future<void> _refreshUserRoles() async {
    try {
      await AuthService.syncSessionFromMe();
      if (!mounted) return;
      setState(() {
        _hasPassengerRole = UserSession.registeredRoles.contains('passenger');
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _hasPassengerRole = UserSession.registeredRoles.contains('passenger');
    _refreshUserRoles();
    _loadRequests();
    _loadMyRidesAndRestore();
    _loadActiveRides();
    _connectRequestWebSocket();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _loadRequests();
        _loadMyRides();
        _loadActiveRides();
      }
    });
  }

  void _connectRequestWebSocket() {
    final driverId = UserSession.studentId;
    if (driverId.isEmpty) return;

    final baseUri = Uri.parse(ApiConfig.baseUrl);
    final wsUri = baseUri.replace(
      scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/driver/$driverId',
      queryParameters: UserSession.token.isEmpty ? null : {'token': UserSession.token},
    );

    try {
      _requestChannel = WebSocketChannel.connect(wsUri);
      _requestChannel!.stream.listen(
        _handleRequestSocketMessage,
        onError: (_) => _requestChannel = null,
        onDone: () => _requestChannel = null,
      );
    } catch (_) {
      _requestChannel = null;
    }
  }

  void _handleRequestSocketMessage(dynamic data) {
    try {
      final decoded = jsonDecode(data as String);
      if (decoded is! Map || decoded['type'] != 'new_ride_request') return;
      final rawRequest = decoded['request'];
      if (rawRequest is! Map) return;
      final request = RideService.mapDriverRequestForUi(
        Map<String, dynamic>.from(rawRequest),
      );
      if (!mounted) return;
      setState(() {
        final id = request['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          _requests.removeWhere((r) => r['id']?.toString() == id);
        }
        _requests.insert(0, request);
      });
    } catch (_) {}
  }

 Future<void> _loadActiveRides() async{
  try{
    final list=await RideService.fetchActiveRides();
    if(!mounted)return;
    setState((){
      _activeRides
        ..clear()
        ..addAll(list.where((r){
          final status=r['status']?.toString().toLowerCase()??'';
          return status!='completed'&&status!='cancelled'&&status!='ended';
        }));
      _syncActiveRideId([..._myRides,..._activeRides]);
    });
  }catch(_){}
}

  /// Reload posted rides without auto-navigation.
  Future<void> _loadMyRides() async {
    setState(() => _loadingMyRides = true);
    try {
      final list = await RideService.fetchMyRides();
      if (!mounted) return;

      setState(() {
        _myRides
          ..clear()
          ..addAll(list.where(
              (r) => r['status'] != 'completed' && r['status'] != 'cancelled' && r['status'] != 'ended'));
        _syncActiveRideId([..._myRides, ..._activeRides]);
        _loadingMyRides = false;
      });
      await _loadActiveRides();
    } catch (_) {
      if (mounted) setState(() => _loadingMyRides = false);
    }
  }

  /// On first open, reload rides and restore activeRideId (no forced navigation).
  Future<void> _loadMyRidesAndRestore() async {
    setState(() => _loadingMyRides = true);
    try {
      final list = await RideService.fetchMyRides();
      if (!mounted) return;

      setState(() {
        _myRides
          ..clear()
          ..addAll(list.where(
              (r) => r['status'] != 'completed' && r['status'] != 'cancelled' && r['status'] != 'ended'));
        _syncActiveRideId([..._myRides, ..._activeRides]);
        _loadingMyRides = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMyRides = false);
    }
  }

  void _openRideManagement(Map<String, dynamic> ride) {
    final passengers = ride['accepted_passengers'] as List? ?? [];
    final firstPax = passengers.isNotEmpty
        ? passengers[0] as Map<String, dynamic>
        : <String, dynamic>{};
    final rideId = ride['id']?.toString() ?? ride['ride_id']?.toString() ?? '';
    UserSession.activeRideId = rideId;
    final req = {
      ...ride,
      'ride_id': rideId,
      'passenger_name': firstPax['name'] ?? 'Passenger',
      'passenger_phone': firstPax['phone'] ?? '',
      'from_address': ride['from_address'] ?? ride['pickup'] ?? '',
      'to_address': ride['to_address'] ?? ride['destination'] ?? '',
    };
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverRideManagementScreen(request: req),
      ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _requestChannel?.sink.close();
    super.dispose();
  }


  Future<void> _cancelRideById(String rideId) async {
    if (rideId.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Ride'),
        content: const Text('Are you sure you want to cancel this ride?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await RideService.cancelRide(rideId);
      TopRightAlert.show(context, title: 'Ride Cancelled', message: 'Ride deleted.', isError: false);
      _loadMyRides();
    } catch (e) {
      TopRightAlert.show(context, title: 'Error', message: e.toString(), isError: true);
    }
  }

  Future<void> _editRide(Map<String, dynamic> ride) async {
    final fareCtrl = TextEditingController(text: ride['fare_per_seat']?.toString() ?? '');
    final seatsCtrl = TextEditingController(text: ride['seats_available']?.toString() ?? '');
    final rideId = ride['id']?.toString() ?? '';

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Edit Ride', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00897B))),
            const SizedBox(height: 16),
            TextField(controller: fareCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Fare per seat (Rs.)',
                  border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: seatsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Available Seats',
                  border: OutlineInputBorder())),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00897B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    await RideService.editRide(rideId, {
                      'fare_per_seat': double.tryParse(fareCtrl.text) ?? ride['fare_per_seat'],
                      'seats_available': int.tryParse(seatsCtrl.text) ?? ride['seats_available'],
                    });
                    TopRightAlert.show(context, title: 'Updated ✅', message: 'Ride updated.', isError: false);
                    _loadMyRides();
                  } catch (e) {
                    TopRightAlert.show(context, title: 'Error', message: e.toString(), isError: true);
                  }
                },
                child: const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _completeRide(String rideId) async {
    try {
      await RideService.completeRide(rideId);
      TopRightAlert.show(context,
          title: 'Ride Completed ✅',
          message: 'Ride has been marked as completed.',
          isError: false);
      _loadMyRides();
      _loadRequests();
      _loadActiveRides();
    } catch (e) {
      TopRightAlert.show(context,
          title: 'Error',
          message: e.toString().replaceFirst('Exception: ', ''),
          isError: true);
    }
  }

  Future<void> _loadRequests() async {
    setState(() => _loadingRequests = true);
    try {
      final list = await RideService.fetchDriverRequests();
      if (!mounted) return;
      setState(() {
        _requests
          ..clear()
          ..addAll(list);
        _loadingRequests = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  Future<void> _acceptRequest(String id) async {
    try {
      await RideService.acceptRequest(id);

      // Remove from requests list immediately
      final req = _requests.firstWhere(
        (r) => r['id'].toString() == id.toString(),
        orElse: () => {},
      );
      setState(() => _requests.removeWhere(
          (r) => r['id'].toString() == id.toString()));

      UserSession.activeRideId = req['ride_id']?.toString() ?? req['id']?.toString() ?? '';

      if (!mounted) return;
      TopRightAlert.show(
        context,
        title: 'Request Accepted ✅',
        message: 'Ride started!',
        isError: false,
      );

      await _loadMyRides();
      await _loadActiveRides();

      if (!mounted) return;
      final rideId = req['ride_id']?.toString() ?? req['id']?.toString() ?? '';
      
      final matchingRide = [..._myRides, ..._activeRides].firstWhere(
        (r) {
          final rId = r['id']?.toString() ?? r['ride_id']?.toString() ?? '';
          return rId == rideId;
        },
        orElse: () => {},
      );

      if (matchingRide.isNotEmpty) {
        _openRideManagement(matchingRide);
      } else {
        final navReq = {
          ...req,
          'ride_id': rideId,
          'request_id': id,
        };
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DriverRideManagementScreen(request: navReq),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      TopRightAlert.show(
        context,
        title: 'Error',
        message: e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _rejectRequest(dynamic id) async {
    try {
      await RideService.rejectRequest(id.toString());
      setState(() => _requests.removeWhere((r) => r['id'].toString() == id.toString()));
      if (!mounted) return;
      TopRightAlert.show(
        context,
        title: 'Request Declined',
        message: 'Request declined.',
        isError: false,
      );
    } catch (e) {
      if (!mounted) return;
      TopRightAlert.show(
        context,
        title: 'Error',
        message: e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingRequests =
    _requests.where((r) => r['status'] == 'pending').toList();
    final currentActiveRide = _currentActiveRide;

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          Positioned.fill(
            child: OsmLiveTrackingMap(
              pickupText: currentActiveRide?['from_address'] ?? '',
              destinationText: currentActiveRide?['to_address'] ?? '',
              enableLiveLocation: true,
            ),
          ),

          // Top bar
          SafeArea(
            child: Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Back
                  Material(
                    elevation: 3,
                    shape: const CircleBorder(),
                    color: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new,
                          color: Color(0xFF00897B), size: 18),
                      onPressed: () => Navigator.pushReplacement(context,
                          MaterialPageRoute(builder: (_) => const OfferRidePage())),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Menu
                  Material(
                    elevation: 3,
                    shape: const CircleBorder(),
                    color: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.menu_rounded,
                          color: Color(0xFF00897B), size: 22),
                      onPressed: () =>
                          _scaffoldKey.currentState?.openDrawer(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Status chip
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 10)
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isOnline
                                  ? const Color(0xFF00897B)
                                  : Colors.grey,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _isOnline
                                  ? 'Online — accepting requests'
                                  : 'Offline',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _isOnline
                                      ? const Color(0xFF00897B)
                                      : Colors.grey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Spacer(),
                          // Online/Offline toggle
                          GestureDetector(
                            onTap: () =>
                                setState(() => _isOnline = !_isOnline),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 40,
                              height: 22,
                              decoration: BoxDecoration(
                                color: _isOnline
                                    ? const Color(0xFF00897B)
                                    : Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: AnimatedAlign(
                                duration: const Duration(milliseconds: 200),
                                alignment: _isOnline
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.all(2),
                                  width: 18,
                                  height: 18,
                                  decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom sheet with tabs
          DraggableScrollableSheet(
            initialChildSize: 0.50,
            minChildSize: 0.38,
            maxChildSize: 0.92,
            builder: (context, scrollController) {
              return DefaultTabController(
                length: 2,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)],
                  ),
                  child: Column(
                    children: [
                      // Drag handle
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 50, height: 5,
                          decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Tab bar
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F4F7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TabBar(
                          indicator: BoxDecoration(
                            color: const Color(0xFF00897B),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          indicatorSize: TabBarIndicatorSize.tab,
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.grey.shade600,
                          labelStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                          dividerColor: Colors.transparent,
                          tabs: [
                            Tab(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.directions_car_outlined, size: 16),
                                  const SizedBox(width: 6),
                                  const Text('My Rides'),
                                  if (_myRides.isNotEmpty) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text('${_myRides.length}',
                                          style: const TextStyle(fontSize: 11)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Tab(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.person_add_outlined, size: 16),
                                  const SizedBox(width: 6),
                                  const Text('Requests'),
                                  if (pendingRequests.isNotEmpty) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.8),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text('${pendingRequests.length}',
                                          style: const TextStyle(fontSize: 11, color: Colors.white)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Tab content
                      Expanded(
                        child: TabBarView(
                          children: [
                            // ── Tab 1: My Posted Rides ──
                            _loadingMyRides
                                ? const Center(child: CircularProgressIndicator(
                                    color: Color(0xFF00897B)))
                                : _myRides.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.directions_car_outlined,
                                            size: 48, color: Colors.grey.shade300),
                                        const SizedBox(height: 12),
                                        Text('No rides posted yet',
                                            style: TextStyle(color: Colors.grey.shade500)),
                                        const SizedBox(height: 8),
                                        TextButton(
                                          onPressed: () => Navigator.pushReplacement(context,
                                              MaterialPageRoute(builder: (_) => const OfferRidePage())),
                                          child: const Text('Post a Ride',
                                              style: TextStyle(color: Color(0xFF00897B))),
                                        ),
                                      ],
                                    ),
                                  )
                                : Column(
                                    children: [
                                      // Post New Ride button
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            onPressed: () => Navigator.push(context,
                                                MaterialPageRoute(builder: (_) => const OfferRidePage())),
                                            icon: const Icon(Icons.add, color: Color(0xFF00897B)),
                                            label: const Text('Post New Ride',
                                                style: TextStyle(color: Color(0xFF00897B), fontWeight: FontWeight.w700)),
                                            style: OutlinedButton.styleFrom(
                                              side: const BorderSide(color: Color(0xFF00897B)),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: ListView.builder(
                                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                                          itemCount: _myRides.length,
                                          itemBuilder: (_, i) => _myRideCard(_myRides[i]),
                                        ),
                                      ),
                                    ],
                                  ),

                            // ── Tab 2: Ride Requests ──
                            !_isOnline
                                ? Center(child: _offlineBanner())
                                : _loadingRequests
                                ? const Center(child: CircularProgressIndicator(
                                    color: Color(0xFF00897B)))
                                : pendingRequests.isEmpty
                                ? Center(child: _emptyState())
                                : ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                                    itemCount: pendingRequests.length,
                                    itemBuilder: (_, i) => _requestCard(pendingRequests[i]),
                                  ),
                          ],
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

  Widget _requestCard(Map<String, dynamic> req) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: passenger + fare
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFE0F2F1),
                child: Icon(
                  req['gender'] == 'Female' ? Icons.face_3 : Icons.face,
                  color: const Color(0xFF00897B),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(req['passenger_name'] ?? req['passengerName'] ?? 'Passenger',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF212121))),
                    Text('${req['seats'] ?? 1} seat',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Rs. ${req['fare'] ?? 0}',
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF00897B))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 12),

          // Route
          Row(
            children: [
              Column(
                children: [
                  const Icon(Icons.my_location,
                      size: 13, color: Color(0xFF00897B)),
                  Container(
                      width: 1, height: 14, color: Colors.grey.shade300),
                  const Icon(Icons.location_on,
                      size: 13, color: Colors.redAccent),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req['from_address'] ?? req['pickup'] ?? '-',
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w600, color: Color(0xFF212121)),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      req['to_address'] ?? req['destination'] ?? '-',
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w600, color: Color(0xFF212121)),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Accept / Reject buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rejectRequest(req['id']),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Decline',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => _acceptRequest(req['id']),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Accept',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _offlineBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.wifi_off_rounded, size: 50, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text('Offline',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Toggle online to start receiving requests.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _myRideCard(Map<String, dynamic> ride) {
    final status = ride['status']?.toString() ?? 'active';
    final isOngoing=status=='ongoing'||status=='started'||status=='in_progress';
    final hasPassengers = (ride['accepted_count'] ?? 0) > 0;

    return GestureDetector(
      onTap: hasPassengers || isOngoing ? () => _openRideManagement(ride) : null,
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isOngoing
            ? const Color(0xFF00897B).withOpacity(0.08)
            : const Color(0xFFE0F2F1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOngoing
              ? const Color(0xFF00897B)
              : const Color(0xFF00897B).withOpacity(0.2),
          width: isOngoing ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.my_location, color: Color(0xFF00897B), size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(
              ride['from_address']?.toString() ?? '-',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            )),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.location_on, color: Colors.redAccent, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(
              ride['to_address']?.toString() ?? '-',
              style: const TextStyle(fontSize: 13),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            )),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
            _chip(Icons.access_time, TimeUtils.formatDateTimeShort(ride['departure_time']?.toString())),
            _chip(Icons.payments_outlined, 'Rs. ${ride['fare_per_seat'] ?? 0}'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isOngoing
                    ? const Color(0xFF00897B).withOpacity(0.15)
                    : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isOngoing ? '🟢 Ongoing' : status,
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: isOngoing ? const Color(0xFF00897B) : Colors.green,
                ),
              ),
            ),
          ]),

          // Accepted passengers
          if ((ride['accepted_count'] ?? 0) > 0) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.people, size: 14, color: Color(0xFF00897B)),
              const SizedBox(width: 6),
              Text('${ride['accepted_count']} passenger(s) booked',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: Color(0xFF00897B))),
            ]),
            const SizedBox(height: 4),
            ...(ride['accepted_passengers'] as List? ?? []).map((p) =>
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 20),
                    const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text('${p['name']}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Edit / Cancel buttons — sirf active rides ke liye (no passengers yet and not started)
          if (status == 'active' && (ride['accepted_count'] ?? 0) == 0) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _editRide(ride),
                  icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF00897B)),
                  label: const Text('Edit', style: TextStyle(color: Color(0xFF00897B))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF00897B)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _cancelRideById(ride['id']?.toString() ?? ''),
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                  label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ]),
          ],
        ],
      ),
    ),  // end child Container
    );  // end GestureDetector
  }

  Widget _chip(IconData icon, String label) {
    return Row(children: [
      Icon(icon, size: 13, color: Colors.grey.shade600),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
    ]);
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 50, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text('No pending requests',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('New ride requests will appear here.',
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.75,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.only(
                  top: 60, left: 20, right: 20, bottom: 30),
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF00897B),
                borderRadius:
                BorderRadius.only(topRight: Radius.circular(30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 35,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.directions_car,
                        size: 40, color: Color(0xFF00897B)),
                  ),
                  const SizedBox(height: 15),
                  Text(UserSession.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  Text('Rider ID: ${UserSession.studentId}',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _drawerTile(Icons.person_outline, 'My Profile', () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const DriverProfileScreen()));
            }),
            _drawerTile(Icons.payments_outlined, 'My Earnings', () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const DriverEarningsScreen()));
            }),
            _drawerTile(Icons.history_rounded, 'Ride History', () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RideHistoryScreen()));
            }),
            _drawerTile(Icons.notifications_outlined, 'Notifications', () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()));
            }),
            if (_hasPassengerRole)
              _drawerTile(Icons.hail_outlined, 'Switch to Passenger', () async {
                Navigator.pop(context);
                try {
                  await AuthService.switchMode('passenger');
                  UserSession.activeRole = 'passenger';
                  await UserSession.save();
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const RideSearchScreen()),
                    (_) => false,
                  );
                } catch (e) {
                  TopRightAlert.show(context,
                      title: 'Switch Failed',
                      message: e.toString().replaceFirst('Exception: ', ''),
                      isError: true);
                }
              })
            else
              _drawerTile(Icons.person_add_outlined, 'Create Passenger Account', () async {
                Navigator.pop(context);
                try {
                  await AuthService.enablePassenger();
                  await AuthService.syncSessionFromMe();
                  UserSession.activeRole = 'passenger';
                  await UserSession.save();
                  if (!mounted) return;
                  setState(() => _hasPassengerRole = true);
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const RideSearchScreen()),
                    (_) => false,
                  );
                } catch (e) {
                  TopRightAlert.show(context,
                      title: 'Error',
                      message: e.toString().replaceFirst('Exception: ', ''),
                      isError: true);
                }
              }),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: InkWell(
                onTap: () {
                  UserSession.clear();
                  TopRightAlert.show(context,
                      title: 'Signed out',
                      message: 'You have been signed out.',
                      isError: false);
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const HamrahLoginPage()),
                        (route) => false,
                  );
                },
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 15, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.logout_rounded, color: Colors.red),
                      SizedBox(width: 15),
                      Text('Logout',
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _drawerTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
      leading: Icon(icon, color: const Color(0xFF00897B), size: 22),
      title: Text(label,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF212121))),
      trailing:
      const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      onTap: onTap,
    );
  }
}
